import CloudKit
import Foundation
import os
import SwiftData

/// What the sync engine does with the store, apart from CloudKit itself, so it can be tested with a fake server:
///
/// - **Out:** reads SwiftData history since the last time (`localChanges()`) and turns this device's saves into
///   records to save or delete, and books into zones. Builds each record when the engine asks (`record(for:)`).
/// - **In:** applies fetched records and deletions (`applyFetched`), and deleted zones (`applyDeletedZone`), saving
///   them with the author `"sync"` so they aren't sent back.
/// - **Results:** keeps each saved record's system fields (`didSave`), and handles refused saves (`didFail`):
///   conflicts are merged, records deleted elsewhere are deleted here.
@MainActor
final class SyncProcessor {
    /// The author of saves made by sync, which `localChanges()` skips.
    static let author = "sync"

    /// A change to send to CloudKit.
    enum Change: Hashable {
        case saveZone(CKRecordZone.ID)
        case deleteZone(CKRecordZone.ID)
        case saveRecord(CKRecord.ID)
        case deleteRecord(CKRecord.ID)
        /// A record added and deleted before it was ever sent: drop any pending save with this name.
        case cancelSave(recordName: String)
    }

    let context: ModelContext
    /// Where `localChanges()` last read up to. Saved by the caller.
    var historyToken: DefaultHistoryToken?
    /// Fetched records whose references haven't arrived yet, by zone. Saved by the caller.
    var pendingReferences: [CKRecordZone.ID: [CKRecord]] = [:]

    private let log = Logger(subsystem: "net.s-church.stirlingmoney", category: "Sync")

    init(context: ModelContext, historyToken: DefaultHistoryToken? = nil) {
        self.context = context
        self.historyToken = historyToken
    }

    // MARK: - Out

    /// Every change this device saved since the last call, skipping sync's own.
    func localChanges() throws -> [Change] {
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>()
        if let token = historyToken {
            descriptor.predicate = #Predicate { $0.token > token }
        }
        let transactions = try context.fetchHistory(descriptor)
        var changes: [Change] = []
        for transaction in transactions where transaction.author != Self.author {
            for change in transaction.changes {
                switch change {
                case let .insert(insert):
                    changes += try saved(insert.changedPersistentIdentifier, isNew: true)
                case let .update(update):
                    if Self.changesSyncedValues(update) {
                        changes += try saved(update.changedPersistentIdentifier, isNew: false)
                    }
                case let .delete(delete):
                    changes += deleted(delete)
                @unknown default:
                    break
                }
            }
        }
        historyToken = transactions.last?.token ?? historyToken
        return try withoutGoneBooks(Self.collapse(changes))
    }

    /// Drops changes to the records of books that are no longer here, or that this user may only view.
    ///
    /// Deleting a book deletes everything in it, and each of those deletes is in the history. For the user's own
    /// book, the zone's deletion already removes them. For a book someone else shared, they must never be sent:
    /// leaving would otherwise delete the owner's records. Only the share's own deletion (leaving) goes.
    ///
    /// A View Only book can't be changed in the app; anything that changes it anyway (a migration, a fix-up) stays
    /// on this device instead of being refused by CloudKit.
    func withoutGoneBooks(_ changes: [Change]) throws -> [Change] {
        var bookIsHere: [CKRecordZone.ID: Bool] = [:]
        return try changes.filter { change in
            let recordID: CKRecord.ID
            switch change {
            case let .saveRecord(id), let .deleteRecord(id): recordID = id
            case .saveZone, .deleteZone, .cancelSave: return true
            }
            if recordID.recordName == CKRecordNameZoneWideShare {
                return true
            }
            let zoneID = recordID.zoneID
            if let known = bookIsHere[zoneID] {
                return known
            }
            let isHere = try book(for: zoneID)?.canEdit ?? false
            bookIsHere[zoneID] = isHere
            return isHere
        }
    }

    /// Everything in the user's own books, for the first upload from this device. Books shared with the user are
    /// the owner's to upload.
    func allChanges() throws -> [Change] {
        var changes: [Change] = []
        for book in try context.fetch(FetchDescriptor<Book>()) where book.zoneOwnerName == nil {
            changes.append(.saveZone(book.zoneID))
            changes += book.allRecords().map { .saveRecord($0.recordID) }
        }
        return changes
    }

    /// Drops history this device has already read, so the store doesn't keep it forever.
    func pruneHistory() throws {
        guard let token = historyToken else { return }
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>()
        descriptor.predicate = #Predicate { $0.token < token }
        try context.deleteHistory(descriptor)
    }

    /// One change per record or zone, the last one winning (a save then a delete is a delete). Zones come first.
    static func collapse(_ changes: [Change]) -> [Change] {
        var latest: [String: Change] = [:]
        var order: [String] = []
        for change in changes {
            let key: String
            switch change {
            case let .saveZone(id), let .deleteZone(id): key = "zone:\(id.zoneName):\(id.ownerName)"
            case let .saveRecord(id), let .deleteRecord(id): key = "record:\(id.recordName)"
            case let .cancelSave(name): key = "record:\(name)"
            }
            if latest[key] == nil {
                order.append(key)
            }
            latest[key] = change
        }
        let all = order.compactMap { latest[$0] }
        let zones = all.filter {
            if case .saveZone = $0 {
                true
            } else if case .deleteZone = $0 {
                true
            } else {
                false
            }
        }
        return zones + all.filter { !zones.contains($0) }
    }

    private func saved(_ id: PersistentIdentifier, isNew: Bool) throws -> [Change] {
        if id.entityName == "Book" {
            guard let book = try fetch(Book.self, id) else { return [] }
            let record = Change.saveRecord(CKRecord.ID(recordName: book.syncID, zoneID: book.zoneID))
            return isNew ? [.saveZone(book.zoneID), record] : [record]
        }
        guard let model = try model(id), let zoneID = (model as? any BookOwned)?.book?.zoneID else { return [] }
        return [.saveRecord(CKRecord.ID(recordName: model.syncID, zoneID: zoneID))]
    }

    /// Whether an update touched anything a record holds. Adding a transaction also "updates" its account and book
    /// (their lists of transactions), which needn't be sent.
    private static func changesSyncedValues(_ update: any HistoryUpdate) -> Bool {
        func changed<T: PersistentModel>(_: T.Type, ignoring ignored: [PartialKeyPath<T>]) -> Bool? {
            guard let update = update as? DefaultHistoryUpdate<T> else { return nil }
            return update.updatedAttributes.contains { !ignored.contains($0) }
        }
        let bookKeys: [PartialKeyPath<Book>] = [
            \.accounts, \.categories, \.budgets, \.goals, \.recurringTransactions, \.transactions,
            \.ckSystemFields, \.ckSyncedValues,
            // Sharing state is this device's copy of the share, not part of the book's record.
            \.isShared, \.isOwnedByMe, \.canEdit, \.ownerName, \.zoneOwnerName,
        ]
        return changed(Book.self, ignoring: bookKeys)
            ?? changed(Account.self, ignoring: [
                \.transactions, \.goals, \.recurringTransactions, \.recurringTransfersIn, \.ckSystemFields, \.ckSyncedValues,
            ])
            ?? changed(Category.self, ignoring: [
                \.transactions, \.budgets, \.recurringTransactions, \.ckSystemFields, \.ckSyncedValues,
            ])
            ?? changed(RecurringTransaction.self, ignoring: [\.transactions, \.ckSystemFields, \.ckSyncedValues])
            ?? changed(AccountTransaction.self, ignoring: [\.outgoingHalf, \.ckSystemFields, \.ckSyncedValues])
            ?? changed(Budget.self, ignoring: [\.ckSystemFields, \.ckSyncedValues])
            ?? changed(Goal.self, ignoring: [\.ckSystemFields, \.ckSyncedValues])
            ?? true
    }

    private func deleted(_ delete: any HistoryDelete) -> [Change] {
        if let book = delete as? DefaultHistoryDelete<Book> {
            guard let syncID = book.tombstone[\.syncID] as? String else { return [] }
            if let owner = book.tombstone[\.zoneOwnerName] as? String {
                // Someone else's book: deleting it here leaves their share. Their zone stays.
                let zoneID = CKRecordZone.ID(zoneName: Book.zonePrefix + syncID, ownerName: owner)
                return [.deleteRecord(Self.shareID(in: zoneID))]
            }
            let zoneID = CKRecordZone.ID(zoneName: Book.zonePrefix + syncID, ownerName: CKCurrentUserDefaultName)
            return [.deleteZone(zoneID)]
        }
        guard let (syncID, fields) = Self.tombstoneValues(delete) else { return [] }
        if let fields, let record = CKRecord.decodingSystemFields(from: fields) {
            return [.deleteRecord(record.recordID)]
        }
        // Never synced: there's nothing on the server, but a save may still be waiting to go.
        return syncID.map { [.cancelSave(recordName: $0)] } ?? []
    }

    /// The `syncID` and system fields kept in a deleted model's tombstone.
    private static func tombstoneValues(_ delete: any HistoryDelete) -> (syncID: String?, fields: Data?)? {
        func values<T: CloudRecordMapped>(_: T.Type) -> (String?, Data?)? {
            guard let delete = delete as? DefaultHistoryDelete<T> else { return nil }
            return (delete.tombstone[\.syncID] as? String, delete.tombstone[\.ckSystemFields] as? Data)
        }
        return values(Account.self) ?? values(AccountTransaction.self) ?? values(Category.self)
            ?? values(Budget.self) ?? values(Goal.self) ?? values(RecurringTransaction.self)
    }

    // MARK: - Records the engine sends

    /// Records on their way to the server, by ID: what each save sent, which becomes the common ancestor once it's
    /// accepted. The server's answer to a save carries its new system fields but not necessarily its values.
    private var sent: [CKRecord.ID: CKRecord] = [:]

    /// The record to save for `recordID`, built from the model now, or nil if it's gone.
    func record(for recordID: CKRecord.ID) throws -> CKRecord? {
        guard let book = try book(for: recordID.zoneID) else { return nil }
        let record: CKRecord?
        if recordID.recordName == book.syncID {
            record = book.makeRecord()
        } else {
            record = try model(named: recordID.recordName, in: book)?.makeRecord(in: book.zoneID)
        }
        sent[recordID] = record?.copy() as? CKRecord
        return record
    }

    // MARK: - In

    /// Applies fetched records and deletions, and saves. Returns saves for records merged with changes this device
    /// hadn't sent: the merge was made by sync, so nothing else would send it.
    @discardableResult
    func applyFetched(_ records: [CKRecord], deletions: [(id: CKRecord.ID, type: CKRecord.RecordType)]) throws -> [Change] {
        var changes: [Change] = []
        try asSync {
            // A zone-wide share comes with the zone's records: it says who owns the book and what this user may do.
            let shares = records.compactMap { $0 as? CKShare }
            let records = records.filter { !($0 is CKShare) }
            for share in shares {
                let book = try book(for: share.recordID.zoneID) ?? makeBook(for: share.recordID.zoneID)
                Self.apply(share, to: book)
            }
            for (zoneID, zoneRecords) in Dictionary(grouping: records, by: \.recordID.zoneID) {
                let book = try book(for: zoneID) ?? makeBook(for: zoneID)
                let unresolved = try RecordImporter.apply(
                    zoneRecords, to: book, in: context, retrying: pendingReferences[zoneID] ?? [],
                    merged: { changes.append(.saveRecord($0)) }
                )
                pendingReferences[zoneID] = unresolved.isEmpty ? nil : unresolved
            }
            for deletion in deletions {
                guard let book = try book(for: deletion.id.zoneID) else { continue }
                if deletion.type == Book.recordType {
                    continue // The book goes when its zone does.
                }
                if deletion.type == CKRecord.SystemType.share {
                    // Sharing stopped. For someone else's book, its zone's deletion follows and removes it.
                    book.isShared = false
                    continue
                }
                if let model = try model(named: deletion.id.recordName, in: book) {
                    context.delete(model)
                }
            }
        }
        // Another device may have made a category this one also has. Merging is this device's own change, so it's
        // saved without the sync author and goes up like any edit.
        if records.contains(where: { $0.recordType == Category.recordType }),
           try CategoryMerger.mergeDuplicates(in: context) > 0
        {
            try context.save()
        }
        return changes
    }

    // MARK: - Sharing

    /// The record ID of a zone's zone-wide share.
    nonisolated static func shareID(in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
    }

    /// Whether a zone is someone else's, so it lives in the shared database (and the shared engine sends its changes).
    nonisolated static func isSharedWithUser(_ zoneID: CKRecordZone.ID) -> Bool {
        zoneID.ownerName != CKCurrentUserDefaultName
    }

    /// Copies a book's share into its sharing state: shared, who owns it, and whether this user may edit it.
    static func apply(_ share: CKShare, to book: Book) {
        book.isShared = true
        let ownedByMe = book.zoneOwnerName == nil
        book.isOwnedByMe = ownedByMe
        // The owner's name, when CloudKit shares it with this user. It often comes as empty components.
        let name = share.owner.userIdentity.nameComponents
            .map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
            .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        if let name {
            book.ownerName = name
        }
        book.canEdit = ownedByMe || share.currentUserParticipant?.permission == .readWrite
    }

    /// Records a share this device just made or fetched for `book`, as sync (it's no change of the user's).
    func didShare(_ book: Book, with share: CKShare) throws {
        try asSync {
            Self.apply(share, to: book)
        }
    }

    /// Records that the owner stopped sharing `book`.
    func didStopSharing(_ book: Book) throws {
        try asSync {
            book.isShared = false
        }
    }

    // MARK: - Account changes

    /// Removes the books other people shared with the user: they belong to the iCloud account that just left.
    func removeSharedBooks() throws {
        try asSync {
            for book in try context.fetch(FetchDescriptor<Book>()) where book.zoneOwnerName != nil {
                context.delete(book)
            }
            pendingReferences = pendingReferences.filter { !Self.isSharedWithUser($0.key) }
        }
    }

    /// Forgets what the old account's server had: every model's system fields and synced values, so the next upload
    /// (to whichever account) starts fresh and conflicts aren't judged against another account's records.
    func forgetSyncState() throws {
        try asSync {
            for book in try context.fetch(FetchDescriptor<Book>()) {
                book.ckSystemFields = nil
                book.ckSyncedValues = nil
                book.isShared = false
                for model in ((book.accounts ?? []) as [any CloudRecordMapped]) + (book.categories ?? [])
                    + (book.transactions ?? []) + (book.budgets ?? []) + (book.goals ?? []) + (book.recurringTransactions ?? [])
                {
                    model.ckSystemFields = nil
                    model.ckSyncedValues = nil
                }
            }
            pendingReferences = [:]
        }
    }

    /// Removes the user's own books from this device, without sending anything: they stay in the iCloud account
    /// they came from.
    func removeOwnBooks() throws {
        try asSync {
            for book in try context.fetch(FetchDescriptor<Book>()) where book.zoneOwnerName == nil {
                context.delete(book)
            }
        }
    }

    /// A book's zone was deleted (or a share stopped): the book goes too.
    func applyDeletedZone(_ zoneID: CKRecordZone.ID) throws {
        try asSync {
            if let book = try book(for: zoneID) {
                context.delete(book)
            }
            pendingReferences[zoneID] = nil
        }
    }

    // MARK: - Results

    /// Keeps the system fields of records the server accepted. Returns deletes for any whose model was deleted
    /// here while the save was on its way.
    func didSave(_ records: [CKRecord]) throws -> [Change] {
        var changes: [Change] = []
        try asSync {
            for record in records {
                // The values this device sent are what both sides now agree on.
                let agreed = RecordMerger.encode(RecordMerger.values(of: sent.removeValue(forKey: record.recordID) ?? record))
                guard let book = try book(for: record.recordID.zoneID) else {
                    continue
                }
                if record.recordID.recordName == book.syncID {
                    book.remember(record)
                    book.ckSyncedValues = agreed
                } else if let model = try model(named: record.recordID.recordName, in: book) {
                    model.remember(record)
                    model.ckSyncedValues = agreed
                } else {
                    changes.append(.deleteRecord(record.recordID))
                }
            }
        }
        return changes
    }

    /// Handles a save the server refused. Returns what to send again.
    func didFail(_ record: CKRecord, error: CKError) throws -> [Change] {
        let recordID = record.recordID
        sent[recordID] = nil
        guard let book = try book(for: recordID.zoneID) else { return [] }
        let isBook = recordID.recordName == book.syncID
        let model = isBook ? nil : try self.model(named: recordID.recordName, in: book)

        switch error.code {
        case .serverRecordChanged:
            guard let server = error.serverRecord else { return [] }
            try asSync {
                if isBook {
                    let ancestor = RecordMerger.decode(book.ckSyncedValues)
                    let merged = RecordMerger.merge(local: book.makeRecord(), server: server.copy() as! CKRecord, ancestor: ancestor)
                    book.read(from: merged)
                    book.remember(server)
                } else if let model {
                    let ancestor = RecordMerger.decode(model.ckSyncedValues)
                    let merged = RecordMerger.merge(
                        local: model.makeRecord(in: book.zoneID), server: server.copy() as! CKRecord, ancestor: ancestor
                    )
                    model.read(from: merged)
                    var resolver = RecordResolver(context: context, book: book)
                    model.readReferences(from: merged, resolver: &resolver)
                    // The server's copy is now the common ancestor; the merged values go up on top of it.
                    model.remember(server)
                }
            }
            log.notice("Merged a conflict in a \(record.recordType, privacy: .public)")
            return [.saveRecord(recordID)]

        case .unknownItem:
            // Deleted on another device: deletes win over edits.
            try asSync {
                if let model {
                    context.delete(model)
                }
            }
            return []

        case .zoneNotFound, .userDeletedZone:
            // A book that was synced before has been deleted elsewhere; one that never was needs its zone made.
            if book.ckSystemFields != nil {
                try applyDeletedZone(recordID.zoneID)
                return []
            }
            return [.saveZone(recordID.zoneID), .saveRecord(recordID)]

        default:
            // Network trouble, rate limits and the like: the engine tries again by itself.
            log.error("Couldn't save a \(record.recordType, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Finding models

    /// Runs `body` with this device's own changes saved first, then saves what it changed as `"sync"`.
    private func asSync(_ body: () throws -> Void) throws {
        if context.hasChanges {
            try context.save()
        }
        context.author = Self.author
        defer { context.author = nil }
        try body()
        if context.hasChanges {
            try context.save()
        }
    }

    func book(for zoneID: CKRecordZone.ID) throws -> Book? {
        guard let syncID = Book.syncID(ofZone: zoneID) else { return nil }
        return try context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.syncID == syncID })).first
    }

    /// A book for a zone that arrived from the server, named when its `Book` record arrives.
    private func makeBook(for zoneID: CKRecordZone.ID) throws -> Book {
        let book = Book(name: Books.defaultName)
        book.syncID = Book.syncID(ofZone: zoneID) ?? book.syncID
        if Self.isSharedWithUser(zoneID) {
            book.zoneOwnerName = zoneID.ownerName
            book.isOwnedByMe = false
            book.isShared = true
        }
        context.insert(book)
        return book
    }

    /// The model in `book` with this `syncID`, whatever its type.
    func model(named syncID: String, in book: Book) throws -> (any CloudRecordMapped)? {
        var resolver = RecordResolver(context: context, book: book)
        if let model: Account = try resolver.find(syncID) {
            return model
        }
        if let model: AccountTransaction = try resolver.find(syncID) {
            return model
        }
        if let model: Category = try resolver.find(syncID) {
            return model
        }
        if let model: Budget = try resolver.find(syncID) {
            return model
        }
        if let model: Goal = try resolver.find(syncID) {
            return model
        }
        if let model: RecurringTransaction = try resolver.find(syncID) {
            return model
        }
        return nil
    }

    private func model(_ id: PersistentIdentifier) throws -> (any CloudRecordMapped)? {
        switch id.entityName {
        case "Account": try fetch(Account.self, id)
        case "AccountTransaction": try fetch(AccountTransaction.self, id)
        case "Category": try fetch(Category.self, id)
        case "Budget": try fetch(Budget.self, id)
        case "Goal": try fetch(Goal.self, id)
        case "RecurringTransaction": try fetch(RecurringTransaction.self, id)
        default: nil
        }
    }

    /// The model with this identifier, or nil if it's been deleted since.
    private func fetch<T: PersistentModel>(_: T.Type, _ id: PersistentIdentifier) throws -> T? {
        var descriptor = FetchDescriptor<T>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
