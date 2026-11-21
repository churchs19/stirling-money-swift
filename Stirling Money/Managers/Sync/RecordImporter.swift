import CloudKit
import Foundation
import SwiftData

/// Applies records fetched from CloudKit to the models of one book: updating the model with the record's name
/// (`syncID`), or adding one.
///
/// CloudKit delivers a zone's records in no particular order, and in batches, so a transaction can arrive before its
/// account. Values are applied first, then references. A record whose references aren't all here yet is returned, to
/// be passed in again (`retrying`) with the next batch.
///
/// Doesn't save, and doesn't handle deletions or conflicts; the sync engine does (step 3).
enum RecordImporter {
    /// Applies `records` to `book`, and retries the references of `pending` records from earlier batches.
    /// Returns the records with references still missing. Records of unknown types (from a newer version) are skipped.
    @discardableResult
    static func apply(
        _ records: [CKRecord],
        to book: Book,
        in context: ModelContext,
        retrying pending: [CKRecord] = []
    ) throws -> [CKRecord] {
        var resolver = RecordResolver(context: context, book: book)

        // Values first, so references within the batch can be found.
        var applied: [(any CloudRecordMapped, CKRecord)] = []
        for record in records {
            if record.recordType == Book.recordType {
                book.read(from: record)
                book.remember(record)
                continue
            }
            if let model = try upsert(record, in: book, resolver: &resolver) {
                applied.append((model, record))
            }
        }

        // A newer copy in this batch replaces a pending one.
        let names = Set(records.map(\.recordID.recordName))
        for record in pending where !names.contains(record.recordID.recordName) {
            if let model = try resolver.model(for: record) {
                applied.append((model, record))
            }
        }

        var unresolved: [CKRecord] = []
        for (model, record) in applied {
            resolver.isMissingReferences = false
            model.readReferences(from: record, resolver: &resolver)
            if resolver.isMissingReferences {
                unresolved.append(record)
            }
        }
        return unresolved
    }

    /// Updates the model with the record's name, or inserts one. Returns nil for an unknown record type.
    private static func upsert(_ record: CKRecord, in book: Book, resolver: inout RecordResolver) throws -> (any CloudRecordMapped)? {
        switch record.recordType {
        case Account.recordType: try upsert(Account.self, record, in: book, resolver: &resolver)
        case AccountTransaction.recordType: try upsert(AccountTransaction.self, record, in: book, resolver: &resolver)
        case Category.recordType: try upsert(Category.self, record, in: book, resolver: &resolver)
        case Budget.recordType: try upsert(Budget.self, record, in: book, resolver: &resolver)
        case Goal.recordType: try upsert(Goal.self, record, in: book, resolver: &resolver)
        case RecurringTransaction.recordType: try upsert(RecurringTransaction.self, record, in: book, resolver: &resolver)
        default: nil
        }
    }

    private static func upsert<T: CloudRecordMapped & BookOwned>(
        _: T.Type, _ record: CKRecord, in book: Book, resolver: inout RecordResolver
    ) throws -> T {
        let syncID = record.recordID.recordName
        let model: T
        if let existing: T = try resolver.find(syncID) {
            model = existing
        } else {
            model = T.makeEmpty()
            model.syncID = syncID
            resolver.context.insert(model)
            model.book = book
            resolver.remember(model)
        }
        model.read(from: record)
        model.remember(record)
        return model
    }
}

/// Finds the models that records name, within one book, and sets references to them.
struct RecordResolver {
    let context: ModelContext
    let book: Book
    /// Set when a reference names a record that isn't here yet.
    var isMissingReferences = false
    /// Models already found or added, by type and `syncID`, so a batch doesn't fetch the same one again.
    private var cache: [String: any CloudRecordMapped] = [:]

    init(context: ModelContext, book: Book) {
        self.context = context
        self.book = book
    }

    private static func key(_ type: (some CloudRecordMapped).Type, _ syncID: String) -> String {
        "\(type.recordType):\(syncID)"
    }

    /// The `T` in the book with this `syncID`, if there is one.
    mutating func find<T: CloudRecordMapped>(_ syncID: String) throws -> T? {
        let key = Self.key(T.self, syncID)
        if let cached = cache[key] as? T {
            return cached
        }
        let found = try context.fetch(FetchDescriptor(predicate: T.withSyncID(syncID, in: book))).first
        if let found {
            cache[key] = found
        }
        return found
    }

    mutating func remember<T: CloudRecordMapped>(_ model: T) {
        cache[Self.key(T.self, model.syncID)] = model
    }

    /// The existing model a record is for, or nil if it's gone or of an unknown type.
    mutating func model(for record: CKRecord) throws -> (any CloudRecordMapped)? {
        let name = record.recordID.recordName
        return switch record.recordType {
        case Account.recordType: try find(name) as Account?
        case AccountTransaction.recordType: try find(name) as AccountTransaction?
        case Category.recordType: try find(name) as Category?
        case Budget.recordType: try find(name) as Budget?
        case Goal.recordType: try find(name) as Goal?
        case RecurringTransaction.recordType: try find(name) as RecurringTransaction?
        default: nil
        }
    }

    /// Sets a reference from `record[key]`: nil if there's none, the model it names if that's here, and otherwise
    /// leaves it and notes the reference as missing. Only calls `set` when the value changes, so unchanged models
    /// aren't marked as edited.
    mutating func assign<T: CloudRecordMapped>(_ record: CKRecord, _ key: String, current: T?, set: (T?) -> Void) {
        guard let reference = record.reference(key) else {
            if current != nil {
                set(nil)
            }
            return
        }
        let target: T? = try? find(reference.recordID.recordName)
        guard let target else {
            isMissingReferences = true
            return
        }
        if current?.persistentModelID != target.persistentModelID {
            set(target)
        }
    }
}

// MARK: - Finding and making each model

extension CloudRecordMapped {
    /// Matches the model in `book` with this `syncID`.
    static func withSyncID(_ syncID: String, in book: Book) -> Predicate<Self> {
        predicate(syncID: syncID, bookID: book.syncID)
    }
}

extension Account {
    static func predicate(syncID: String, bookID: String) -> Predicate<Account> {
        #Predicate { $0.syncID == syncID && $0.book?.syncID == bookID }
    }

    static func makeEmpty() -> Account {
        Account(name: "")
    }
}

extension AccountTransaction {
    static func predicate(syncID: String, bookID: String) -> Predicate<AccountTransaction> {
        #Predicate { $0.syncID == syncID && $0.book?.syncID == bookID }
    }

    static func makeEmpty() -> AccountTransaction {
        AccountTransaction(kind: .withdrawal, amount: 0)
    }
}

extension Category {
    static func predicate(syncID: String, bookID: String) -> Predicate<Category> {
        #Predicate { $0.syncID == syncID && $0.book?.syncID == bookID }
    }

    static func makeEmpty() -> Category {
        Category(name: "")
    }
}

extension Budget {
    static func predicate(syncID: String, bookID: String) -> Predicate<Budget> {
        #Predicate { $0.syncID == syncID && $0.book?.syncID == bookID }
    }

    static func makeEmpty() -> Budget {
        Budget(name: "", amount: 0)
    }
}

extension Goal {
    static func predicate(syncID: String, bookID: String) -> Predicate<Goal> {
        #Predicate { $0.syncID == syncID && $0.book?.syncID == bookID }
    }

    static func makeEmpty() -> Goal {
        Goal(name: "", targetAmount: 0, targetDate: .now, initialBalance: 0)
    }
}

extension RecurringTransaction {
    static func predicate(syncID: String, bookID: String) -> Predicate<RecurringTransaction> {
        #Predicate { $0.syncID == syncID && $0.book?.syncID == bookID }
    }

    static func makeEmpty() -> RecurringTransaction {
        RecurringTransaction(kind: .withdrawal, amount: 0, frequency: .monthly, startDate: .now)
    }
}
