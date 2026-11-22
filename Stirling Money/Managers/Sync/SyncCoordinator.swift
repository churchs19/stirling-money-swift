import CloudKit
import Foundation
import os
import SwiftData

/// Runs iCloud sync for the user's own books: a `CKSyncEngine` on the private database, driven by `SyncProcessor`.
///
/// - After each save of the main context, this device's changes are added to the engine's pending changes, which it
///   sends when it sees fit (and asks for each record through `nextRecordZoneChangeBatch`).
/// - Fetched changes, send results and account changes arrive as events (`handleEvent`).
/// - The engine's state, the history token and records waiting for references are saved in Application Support,
///   so nothing is sent or fetched twice across launches.
///
/// Never runs for tests or sample data (`-UseSampleData`), which would upload the sample to the user's iCloud.
@MainActor
final class SyncCoordinator {
    /// Whether sync runs at all. The app has the iCloud (CloudKit) and Push Notifications capabilities; without
    /// them, touching CloudKit crashes.
    static let isEnabled = true
    static let containerIdentifier = "iCloud.net.s-church.stirlingmoney"

    private(set) static var shared: SyncCoordinator?

    private let processor: SyncProcessor
    private var engine: CKSyncEngine?
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
        var engine: CKSyncEngine.State.Serialization?
        var historyToken: DefaultHistoryToken?
        /// `NSKeyedArchiver` data of the records waiting for references.
        var pendingReferences: Data?
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
        let isFirstRun = saved.engine == nil
        let container = CKContainer(identifier: Self.containerIdentifier)
        delegate.coordinator = self
        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: saved.engine,
            delegate: delegate
        )
        engine = CKSyncEngine(configuration)

        if isFirstRun {
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

    // MARK: - Out

    private func enqueueLocalChanges() {
        do {
            try enqueue(processor.localChanges())
            try processor.pruneHistory()
        } catch {
            log.error("Couldn't read local changes: \(error.localizedDescription, privacy: .public)")
        }
        saveState()
    }

    private func enqueue(_ changes: [SyncProcessor.Change]) {
        guard let engine, !changes.isEmpty else { return }
        var database: [CKSyncEngine.PendingDatabaseChange] = []
        var records: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in changes {
            switch change {
            case let .saveZone(zoneID): database.append(.saveZone(CKRecordZone(zoneID: zoneID)))
            case let .deleteZone(zoneID): database.append(.deleteZone(zoneID))
            case let .saveRecord(recordID): records.append(.saveRecord(recordID))
            case let .deleteRecord(recordID): records.append(.deleteRecord(recordID))
            case let .cancelSave(name):
                let waiting = engine.state.pendingRecordZoneChanges.filter {
                    if case let .saveRecord(id) = $0 {
                        id.recordName == name
                    } else {
                        false
                    }
                }
                engine.state.remove(pendingRecordZoneChanges: waiting)
            }
        }
        engine.state.add(pendingDatabaseChanges: database)
        engine.state.add(pendingRecordZoneChanges: records)
    }

    /// The records for the engine's next send, built from the models now.
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
        do {
            switch event {
            case let .stateUpdate(update):
                saved.engine = update.stateSerialization
                saveState()

            case let .accountChange(change):
                switch change.changeType {
                case .signIn:
                    // Send everything, for a new account (or the same one after signing back in).
                    try enqueue(processor.allChanges())
                case .signOut, .switchAccounts:
                    // Local data stays. What happens to it on another Apple ID is decided in step 7.
                    log.notice("The iCloud account changed")
                @unknown default:
                    break
                }

            case let .fetchedDatabaseChanges(changes):
                for deletion in changes.deletions {
                    try processor.applyDeletedZone(deletion.zoneID)
                }

            case let .fetchedRecordZoneChanges(changes):
                enqueue(try processor.applyFetched(
                    changes.modifications.map(\.record),
                    deletions: changes.deletions.map { (id: $0.recordID, type: $0.recordType) }
                ))
                saveState()

            case let .sentRecordZoneChanges(sent):
                try enqueue(processor.didSave(sent.savedRecords))
                for failure in sent.failedRecordSaves {
                    try enqueue(processor.didFail(failure.record, error: failure.error))
                }

            case let .sentDatabaseChanges(sent):
                for failure in sent.failedZoneSaves {
                    log.error("Couldn't save a zone: \(failure.error.localizedDescription, privacy: .public)")
                }

            default:
                break
            }
        } catch {
            log.error("Couldn't apply a sync event: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Asking

    /// Sends and fetches now, such as from "Sync Now" or a push notification.
    func syncNow() async {
        guard let engine else { return }
        do {
            try await engine.sendChanges()
            try await engine.fetchChanges()
        } catch {
            log.error("Sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// The engine's delegate. Its methods may run on any thread; each hops to the main actor, where the store is.
private final class EngineDelegate: CKSyncEngineDelegate, @unchecked Sendable {
    /// Set once, before the engine starts.
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
