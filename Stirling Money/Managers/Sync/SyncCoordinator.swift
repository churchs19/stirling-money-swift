import CloudKit
import Foundation
import os
import SwiftData

/// Runs iCloud sync: two `CKSyncEngine`s driven by one `SyncProcessor`.
///
/// - The **private** engine syncs the user's own books: zones in their private database.
/// - The **shared** engine syncs books other people shared with the user: the owners' zones, which appear in the
///   user's shared database once they accept the invitation.
/// - Each change goes to the engine for its zone: a zone owned by someone else is a shared one
///   (`SyncProcessor.isSharedWithUser`).
/// - After each save of the main context, this device's changes are added to the engines' pending changes, which they
///   send when they see fit (and ask for each record through `nextRecordZoneChangeBatch`).
/// - Fetched changes, send results and account changes arrive as events (`handleEvent`).
/// - The engines' state, the history token and records waiting for references are saved in Application Support,
///   so nothing is sent or fetched twice across launches.
///
/// Never runs for tests or sample data (`-UseSampleData`), which would upload the sample to the user's iCloud.
@MainActor
final class SyncCoordinator {
    /// Whether sync runs at all. The app has the iCloud (CloudKit) and Push Notifications capabilities; without
    /// them, touching CloudKit crashes.
    static let isEnabled = true
    nonisolated static let containerIdentifier = "iCloud.net.s-church.stirlingmoney"

    private(set) static var shared: SyncCoordinator?

    /// What Settings shows.
    let status = SyncStatus()

    private let processor: SyncProcessor
    private let container = CKContainer(identifier: containerIdentifier)
    private var privateEngine: CKSyncEngine?
    private var sharedEngine: CKSyncEngine?
    private let delegate = EngineDelegate()
    private var observer: (any NSObjectProtocol)?
    private let stateURL: URL
    private let log = Logger(subsystem: "net.s-church.stirlingmoney", category: "Sync")

    /// Starts syncing `context`'s store. Call once, at launch, after `Books.prepare`.
    static func start(_ context: ModelContext) {
        guard isEnabled, !LaunchMode.isTesting, !LaunchMode.usesSampleData, shared == nil else { return }
        let coordinator = SyncCoordinator(context: context)
        shared = coordinator
        coordinator.begin()
    }

    private init(context: ModelContext) {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        stateURL = folder.appending(path: "Sync-Private.json")
        processor = SyncProcessor(context: context)
    }

    // MARK: - Saved state

    private struct SavedState: Codable {
        /// The private engine's state. (Named before there was a shared engine.)
        var engine: CKSyncEngine.State.Serialization?
        var sharedEngine: CKSyncEngine.State.Serialization?
        var historyToken: DefaultHistoryToken?
        /// `NSKeyedArchiver` data of the records waiting for references.
        var pendingReferences: Data?
        /// The change tokens of this app's own checks while in front (`poll`), by database and by zone. Separate
        /// from the engines' own, which they keep to themselves.
        var pollTokens: [String: Data]?
        /// The iCloud user this device last synced as, to tell signing back in from a different Apple ID.
        var accountID: String?
        /// A different Apple ID signed in, and the user hasn't chosen yet what happens to their own books.
        var ownBooksAwaitChoice: Bool?
    }

    private var saved = SavedState()

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        saved = state
        processor.historyToken = state.historyToken
        if let archive = state.pendingReferences,
           let records = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: CKRecord.self, from: archive)
        {
            processor.pendingReferences = Dictionary(grouping: records, by: \.recordID.zoneID)
        }
    }

    private func saveState() {
        saved.historyToken = processor.historyToken
        let pending = processor.pendingReferences.values.flatMap { $0 }
        saved.pendingReferences = pending.isEmpty
            ? nil
            : try? NSKeyedArchiver.archivedData(withRootObject: pending, requiringSecureCoding: true)
        do {
            try JSONEncoder().encode(saved).write(to: stateURL, options: .atomic)
        } catch {
            log.error("Couldn't save the sync state: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Starting

    private func begin() {
        loadState()
        status.ownBooksAwaitChoice = saved.ownBooksAwaitChoice ?? false
        refreshAccountStatus()
        let isFirstRun = saved.engine == nil
        delegate.coordinator = self
        privateEngine = CKSyncEngine(CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: saved.engine,
            delegate: delegate
        ))
        sharedEngine = CKSyncEngine(CKSyncEngine.Configuration(
            database: container.sharedCloudDatabase,
            stateSerialization: saved.sharedEngine,
            delegate: delegate
        ))

        dropQueuedChangesForGoneBooks()
        if isFirstRun {
            beginFirstSyncActivity()
            // Everything goes up once; history before now is covered by that.
            _ = try? processor.localChanges()
            enqueue((try? processor.allChanges()) ?? [])
        } else {
            enqueueLocalChanges()
        }
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: processor.context, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.enqueueLocalChanges() }
        }
    }

    /// Removes queued record changes for books that are no longer here, such as the deletes queued by leaving a
    /// shared book with a build that sent them (they would delete the owner's records). See `withoutGoneBooks`.
    private func dropQueuedChangesForGoneBooks() {
        for engine in engines {
            let dropped = engine.state.pendingRecordZoneChanges.filter { change in
                let recordID: CKRecord.ID
                switch change {
                case let .saveRecord(id), let .deleteRecord(id): recordID = id
                @unknown default: return false
                }
                guard recordID.recordName != CKRecordNameZoneWideShare else { return false }
                return (try? processor.book(for: recordID.zoneID)) == nil
            }
            if !dropped.isEmpty {
                engine.state.remove(pendingRecordZoneChanges: dropped)
                log.notice("Dropped \(dropped.count, privacy: .public) queued changes for books no longer here")
            }
        }
    }

    private var engines: [CKSyncEngine] {
        [privateEngine, sharedEngine].compactMap(\.self)
    }

    /// The engine for a zone: the shared one for someone else's.
    private func engine(for zoneID: CKRecordZone.ID) -> CKSyncEngine? {
        SyncProcessor.isSharedWithUser(zoneID) ? sharedEngine : privateEngine
    }

    // MARK: - Out

    private func enqueueLocalChanges() {
        do {
            let changes = try processor.localChanges()
            if !changes.isEmpty {
                log.notice("Queued \(changes.count, privacy: .public) local changes")
            }
            enqueue(changes)
            try processor.pruneHistory()
        } catch {
            log.error("Couldn't read local changes: \(error.localizedDescription, privacy: .public)")
        }
        saveState()
    }

    /// Adds changes to the engines' pending changes. Returns whether anything was added to send.
    @discardableResult
    private func enqueue(_ changes: [SyncProcessor.Change]) -> Bool {
        var added = false
        for change in changes {
            // Until the user chooses, nothing of their own goes to a different Apple ID's iCloud.
            if status.ownBooksAwaitChoice, !Self.isForSharedEngine(change) {
                continue
            }
            switch change {
            case let .saveZone(zoneID):
                // Only an owner makes zones.
                guard let engine = engine(for: zoneID), engine === privateEngine else { continue }
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            case let .deleteZone(zoneID):
                guard let engine = engine(for: zoneID), engine === privateEngine else { continue }
                engine.state.add(pendingDatabaseChanges: [.deleteZone(zoneID)])
            case let .saveRecord(recordID):
                guard let engine = engine(for: recordID.zoneID) else { continue }
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            case let .deleteRecord(recordID):
                guard let engine = engine(for: recordID.zoneID) else { continue }
                engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
            case let .cancelSave(name):
                for engine in engines {
                    let waiting = engine.state.pendingRecordZoneChanges.filter {
                        if case let .saveRecord(id) = $0 {
                            id.recordName == name
                        } else {
                            false
                        }
                    }
                    engine.state.remove(pendingRecordZoneChanges: waiting)
                }
                continue
            }
            added = true
        }
        return added
    }

    private static func isForSharedEngine(_ change: SyncProcessor.Change) -> Bool {
        switch change {
        case let .saveZone(zoneID), let .deleteZone(zoneID): SyncProcessor.isSharedWithUser(zoneID)
        case let .saveRecord(id), let .deleteRecord(id): SyncProcessor.isSharedWithUser(id.zoneID)
        case .cancelSave: true
        }
    }

    private var isSendRequested = false

    /// Asks the engines to send, once the event being handled is done.
    ///
    /// An engine schedules a send for new pending changes only when no sync is under way. Changes added while it's
    /// handling a fetch or a send's results (a merge, a retry after a conflict) would otherwise wait for the next
    /// unrelated save.
    ///
    /// The engine stops the app (an assertion) if `sendChanges()` is called from within its event handler, and a
    /// plain `Task` started there counts as within: it inherits the handler's task context. So the send runs in a
    /// detached task, after the event has finished.
    private func requestSend() {
        guard !isSendRequested else { return }
        isSendRequested = true
        Task.detached { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            await self?.sendPendingChanges()
        }
    }

    private func sendPendingChanges() async {
        isSendRequested = false
        for engine in engines
            where !engine.state.pendingRecordZoneChanges.isEmpty || !engine.state.pendingDatabaseChanges.isEmpty
        {
            do {
                try await engine.sendChanges()
            } catch {
                log.error("Couldn't send changes: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The records for an engine's next send, built from the models now.
    fileprivate func nextBatch(_ context: CKSyncEngine.SendChangesContext, engine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = engine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            await MainActor.run {
                do {
                    if let record = try self.processor.record(for: recordID) {
                        return record
                    }
                } catch {
                    self.log.error("Couldn't build a record: \(error.localizedDescription, privacy: .public)")
                }
                // Gone since it was queued: nothing to send.
                engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
        }
    }

    // MARK: - In

    fileprivate func handle(_ event: CKSyncEngine.Event, engine: CKSyncEngine) {
        // Whether this event added changes to send.
        var added = false
        defer {
            if added {
                requestSend()
            }
        }
        do {
            switch event {
            case let .stateUpdate(update):
                if engine === sharedEngine {
                    saved.sharedEngine = update.stateSerialization
                } else {
                    saved.engine = update.stateSerialization
                }
                saveState()

            case let .accountChange(change):
                // Both engines report it; act once.
                guard engine === privateEngine else { break }
                refreshAccountStatus()
                switch change.changeType {
                case let .signIn(currentUser):
                    if let previous = saved.accountID, previous != currentUser.recordName {
                        // Signed out, then a different Apple ID signed in.
                        try switchedAccount(to: currentUser.recordName)
                    } else {
                        // The first sign-in, or the same Apple ID back: send everything.
                        saved.accountID = currentUser.recordName
                        added = try enqueue(processor.allChanges())
                    }
                case .signOut:
                    // The user's own books stay and keep working here; changes go up if the same Apple ID signs
                    // back in. Books others shared belong to the account that left.
                    log.notice("Signed out of iCloud")
                    try processor.removeSharedBooks()
                case let .switchAccounts(_, currentUser):
                    try switchedAccount(to: currentUser.recordName)
                @unknown default:
                    break
                }
                saveState()

            case let .fetchedDatabaseChanges(changes):
                log.notice("\(self.name(of: engine), privacy: .public): \(changes.modifications.count, privacy: .public) zones changed, \(changes.deletions.count, privacy: .public) deleted")
                // In the shared database, a deleted zone is a book the owner stopped sharing (or deleted), or one
                // this user left.
                for deletion in changes.deletions {
                    try processor.applyDeletedZone(deletion.zoneID)
                }

            case let .fetchedRecordZoneChanges(changes):
                status.lastSynced = .now
                log.notice("\(self.name(of: engine), privacy: .public): fetched \(changes.modifications.count, privacy: .public) records, \(changes.deletions.count, privacy: .public) deletions")
                added = try enqueue(processor.applyFetched(
                    changes.modifications.map(\.record),
                    deletions: changes.deletions.map { (id: $0.recordID, type: $0.recordType) }
                ))
                saveState()

            case let .sentRecordZoneChanges(sent):
                status.lastSynced = .now
                status.lastError = sent.failedRecordSaves.first.map { $0.error.localizedDescription }
                log.notice("\(self.name(of: engine), privacy: .public): saved \(sent.savedRecords.count, privacy: .public), deleted \(sent.deletedRecordIDs.count, privacy: .public), \(sent.failedRecordSaves.count, privacy: .public) saves refused")
                for failure in sent.failedRecordSaves {
                    log.notice("Refused \(failure.record.recordType, privacy: .public): \(failure.error.code.rawValue, privacy: .public) \(failure.error.localizedDescription, privacy: .public)")
                }
                added = try enqueue(processor.didSave(sent.savedRecords.filter { !($0 is CKShare) }))
                for failure in sent.failedRecordSaves where try enqueue(processor.didFail(failure.record, error: failure.error)) {
                    added = true
                }

            case let .sentDatabaseChanges(sent):
                for failure in sent.failedZoneSaves {
                    log.error("Couldn't save a zone: \(failure.error.localizedDescription, privacy: .public)")
                }

            case .didFetchChanges:
                firstFetchFinished(by: engine)

            default:
                break
            }
        } catch {
            status.lastError = error.localizedDescription
            log.error("Couldn't apply a sync event: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func name(of engine: CKSyncEngine) -> String {
        engine === sharedEngine ? "Shared" : "Private"
    }

    // MARK: - Checking for changes while in front

    private var pollTask: Task<Void, Never>?

    /// The app came to the front: check for changes now, then every minute while it stays there.
    ///
    /// The engines learn about changes made elsewhere from pushes, and those aren't guaranteed: the owner of a
    /// shared book may get none for a participant's changes, simulators get none, and the system can drop or merge
    /// them. Without a push, the engines' own `fetchChanges()` doesn't ask the server at all. So while the app is in
    /// use it asks the server itself (`poll`).
    func appBecameActive() {
        pollTask?.cancel()
        pollTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                await self?.pollAll()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// The app left the front: stop checking. Pushes and the engines' own scheduling still apply.
    func appResignedActive() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollAll() async {
        for (database, name) in [(container.privateCloudDatabase, "private"), (container.sharedCloudDatabase, "shared")] {
            do {
                try await poll(database, name: name)
            } catch {
                log.error("Couldn't check \(name, privacy: .public) for changes: \(error.localizedDescription, privacy: .public)")
            }
        }
        saveState()
    }

    /// Asks one database which zones changed or went since the last check, then fetches the changed zones' records
    /// and applies them like the engines' own fetches. A record applied twice (here and by an engine) just updates
    /// the same model again.
    ///
    /// The first check only notes where things stand (the engines already fetched everything); later ones apply.
    private func poll(_ database: CKDatabase, name: String) async throws {
        let databaseKey = "db:\(name)"
        let isFirstCheck = pollToken(databaseKey) == nil
        var changedZones: [CKRecordZone.ID] = []
        var deletedZones: [CKRecordZone.ID] = []
        var token = pollToken(databaseKey)
        var moreComing = true
        while moreComing {
            let changes = try await database.databaseChanges(since: token)
            changedZones += changes.modifications.map(\.zoneID)
            deletedZones += changes.deletions.map(\.zoneID)
            token = changes.changeToken
            moreComing = changes.moreComing
        }

        if !isFirstCheck {
            for zoneID in deletedZones {
                try processor.applyDeletedZone(zoneID)
                setPollToken(nil, for: zoneKey(zoneID))
            }
            if !deletedZones.isEmpty {
                log.notice("Check of \(name, privacy: .public): \(deletedZones.count, privacy: .public) zones gone")
            }
        }

        for zoneID in changedZones where Book.syncID(ofZone: zoneID) != nil {
            try await fetchZone(zoneID, from: database, apply: !isFirstCheck || pollToken(zoneKey(zoneID)) != nil)
        }
        setPollToken(token, for: databaseKey)
    }

    /// Fetches one zone's changes since the last check. With `apply` false, only notes the zone's token, fetching
    /// no values.
    private func fetchZone(_ zoneID: CKRecordZone.ID, from database: CKDatabase, apply: Bool) async throws {
        let key = zoneKey(zoneID)
        var token = pollToken(key)
        var records: [CKRecord] = []
        var deletions: [(id: CKRecord.ID, type: CKRecord.RecordType)] = []
        var moreComing = true
        while moreComing {
            let changes = try await database.recordZoneChanges(
                inZoneWith: zoneID, since: token, desiredKeys: apply ? nil : []
            )
            if apply {
                records += changes.modificationResultsByID.values.compactMap { try? $0.get().record }
                deletions += changes.deletions.map { (id: $0.recordID, type: $0.recordType) }
            }
            token = changes.changeToken
            moreComing = changes.moreComing
        }
        if apply, !records.isEmpty || !deletions.isEmpty {
            log.notice("Check of \(zoneID.zoneName, privacy: .public): \(records.count, privacy: .public) records, \(deletions.count, privacy: .public) deletions")
            if enqueue(try processor.applyFetched(records, deletions: deletions)) {
                requestSend()
            }
        }
        setPollToken(token, for: key)
    }

    private func zoneKey(_ zoneID: CKRecordZone.ID) -> String {
        "zone:\(zoneID.ownerName)/\(zoneID.zoneName)"
    }

    private func pollToken(_ key: String) -> CKServerChangeToken? {
        saved.pollTokens?[key].flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }
    }

    private func setPollToken(_ token: CKServerChangeToken?, for key: String) {
        var tokens = saved.pollTokens ?? [:]
        tokens[key] = token.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
        saved.pollTokens = tokens
    }

    // MARK: - Sharing

    /// The book's zone-wide share, made now if it has none yet. Saves the zone first, in case the book hasn't been
    /// sent yet. Only for the user's own books.
    func share(for book: Book) async throws -> CKShare {
        let zoneID = book.zoneID
        let database = container.privateCloudDatabase
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])

        let shareID = SyncProcessor.shareID(in: zoneID)
        let share: CKShare
        if let existing = try? await database.record(for: shareID) as? CKShare {
            share = existing
        } else {
            let newShare = CKShare(recordZoneID: zoneID)
            newShare[CKShare.SystemFieldKey.title] = book.name
            newShare.publicPermission = .none
            let results = try await database.modifyRecords(saving: [newShare], deleting: []).saveResults
            guard let saved = try results[shareID]?.get() as? CKShare else {
                throw CKError(.internalError)
            }
            share = saved
        }
        try processor.didShare(book, with: share)
        // The book's own records go up too, if they haven't.
        enqueueLocalChanges()
        return share
    }

    /// The share for the user's own book with this `syncID`, for the sharing sheet.
    static func share(bookWithID syncID: String) async throws -> CKShare {
        let zoneID = CKRecordZone.ID(zoneName: Book.zonePrefix + syncID, ownerName: CKCurrentUserDefaultName)
        guard let coordinator = shared else { throw CKError(.notAuthenticated) }
        guard let book = try coordinator.processor.book(for: zoneID) else { throw CKError(.unknownItem) }
        return try await coordinator.share(for: book)
    }

    /// Stops sharing one of the user's own books: everyone else loses it.
    func stopSharing(_ book: Book) async throws {
        _ = try await container.privateCloudDatabase.modifyRecords(saving: [], deleting: [SyncProcessor.shareID(in: book.zoneID)])
        try processor.didStopSharing(book)
    }

    /// Accepts an invitation the user tapped, then fetches the book. Returns its `syncID`, to switch to it.
    ///
    /// The whole zone is fetched directly. The shared engine may still hold its place in this zone from an earlier
    /// share of the same book (it doesn't always learn that a zone went), and would then fetch only the changes
    /// since: the new share, but not the book's records.
    func accept(_ metadata: CKShare.Metadata) async throws -> String? {
        status.activity = .joining(bookName: metadata.share[CKShare.SystemFieldKey.title] as? String)
        defer {
            if case .joining = status.activity {
                status.activity = nil
            }
        }
        _ = try await container.accept(metadata)
        let zoneID = metadata.share.recordID.zoneID
        setPollToken(nil, for: zoneKey(zoneID))
        try await fetchZone(zoneID, from: container.sharedCloudDatabase, apply: true)
        saveState()
        try? await sharedEngine?.fetchChanges()
        return Book.syncID(ofZone: zoneID)
    }

    // MARK: - Asking

    /// Sends and fetches now, such as from "Sync Now".
    func syncNow() async {
        guard !status.isSyncing else { return }
        status.isSyncing = true
        defer { status.isSyncing = false }
        refreshAccountStatus()
        do {
            for engine in engines {
                try await engine.sendChanges()
            }
            // The engines' own fetch does nothing without a push; this asks the server.
            await pollAll()
            status.lastSynced = .now
            status.lastError = nil
        } catch {
            status.lastError = error.localizedDescription
            log.error("Sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - The iCloud account

    private func refreshAccountStatus() {
        Task {
            status.account = try? await container.accountStatus()
            // Nothing will arrive without an account.
            if status.account != .available, status.activity == .firstSync {
                status.activity = nil
            }
        }
    }

    // MARK: - The first sync

    /// Engines that haven't finished their first fetch on this device.
    private var awaitingFirstFetch: Set<ObjectIdentifier> = []

    /// Shows the first-sync overlay until both engines have fetched once (or two minutes, whichever comes first).
    private func beginFirstSyncActivity() {
        awaitingFirstFetch = Set(engines.map(ObjectIdentifier.init))
        status.activity = .firstSync
        Task {
            try? await Task.sleep(for: .seconds(120))
            if status.activity == .firstSync {
                status.activity = nil
            }
        }
    }

    private func firstFetchFinished(by engine: CKSyncEngine) {
        guard awaitingFirstFetch.remove(ObjectIdentifier(engine)) != nil, awaitingFirstFetch.isEmpty else { return }
        if status.activity == .firstSync {
            status.activity = nil
        }
    }

    /// A different Apple ID is now signed in. Books shared with the old one go; the user's own books stay here,
    /// unsent, until they choose in Settings (`uploadOwnBooks` or `removeOwnBooks`).
    private func switchedAccount(to accountID: String) throws {
        log.notice("A different Apple ID signed in")
        try processor.removeSharedBooks()
        try processor.forgetSyncState()
        saved.pollTokens = nil
        saved.accountID = accountID
        setOwnBooksAwaitChoice(true)
    }

    private func setOwnBooksAwaitChoice(_ waiting: Bool) {
        status.ownBooksAwaitChoice = waiting
        saved.ownBooksAwaitChoice = waiting
        saveState()
    }

    /// Settings, after a different Apple ID signed in: upload the user's own books to it.
    func uploadOwnBooks() {
        setOwnBooksAwaitChoice(false)
        if enqueue((try? processor.allChanges()) ?? []) {
            requestSend()
        }
    }

    /// Settings, after a different Apple ID signed in: remove the user's own books from this device. They stay in
    /// the old account's iCloud. A new, empty book takes their place.
    func removeOwnBooks() throws {
        try processor.removeOwnBooks()
        setOwnBooksAwaitChoice(false)
        try Books.prepare(in: processor.context)
    }
}

/// The engines' delegate. Its methods may run on any thread; each hops to the main actor, where the store is.
private final class EngineDelegate: CKSyncEngineDelegate, @unchecked Sendable {
    /// Set once, before the engines start.
    weak var coordinator: SyncCoordinator?

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await coordinator?.handle(event, engine: syncEngine)
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await coordinator?.nextBatch(context, engine: syncEngine)
    }
}
