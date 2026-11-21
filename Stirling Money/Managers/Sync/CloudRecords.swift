import CloudKit
import Foundation
import SwiftData

// How each model is stored in CloudKit (Phase 11).
//
// - Each book is a zone, `Book-<syncID>`; everything in the book is a record in that zone, named by its `syncID`.
//   The book itself is a `Book` record in its own zone, holding its name.
// - Field names are the model's property names. Once the schema is deployed to production they can't be renamed or
//   removed, only added to.
// - Values are in `encryptedValues`, so Apple can't read them: names, amounts, payees, notes and dates. References
//   can't be encrypted; they only link records by name.
// - Money (`Decimal`) is a string such as "-12.34", to keep it exact. Booleans and whole numbers are `Int64`.
// - The book isn't a field: it's the zone.

/// A model that's synced as one CloudKit record.
protocol CloudRecordMapped: PersistentModel {
    static var recordType: CKRecord.RecordType { get }
    var syncID: String { get set }
    var ckSystemFields: Data? { get set }
    /// Writes its values and references into `record`.
    func write(to record: CKRecord)
    /// Reads its values (not references) from `record`.
    func read(from record: CKRecord)
    /// Sets its references from `record`, through `resolver`, which notes any it can't find yet.
    func readReferences(from record: CKRecord, resolver: inout RecordResolver)
    /// Matches the model with this `syncID` in the book with `bookID`.
    static func predicate(syncID: String, bookID: String) -> Predicate<Self>
    /// A blank model, filled in from a record.
    static func makeEmpty() -> Self
}

extension CloudRecordMapped {
    /// The record to save for this model in `zoneID`: built on the system fields from the last sync, if any, so
    /// CloudKit can tell whether the server's copy changed since.
    func makeRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let record = ckSystemFields.flatMap(CKRecord.decodingSystemFields(from:))
            ?? CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: syncID, zoneID: zoneID))
        write(to: record)
        return record
    }

    /// Keeps the system fields of a record just saved or fetched.
    func remember(_ record: CKRecord) {
        ckSystemFields = record.encodedSystemFields
    }
}

extension Book {
    /// The CloudKit zone holding the book: in the owner's private database, or for a book shared with this user,
    /// in their shared database under the owner's name.
    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zonePrefix + syncID, ownerName: zoneOwnerName ?? CKCurrentUserDefaultName)
    }

    static let zonePrefix = "Book-"

    /// The book `syncID` a zone belongs to, or nil for a zone that isn't a book's.
    static func syncID(ofZone zoneID: CKRecordZone.ID) -> String? {
        guard zoneID.zoneName.hasPrefix(zonePrefix) else { return nil }
        return String(zoneID.zoneName.dropFirst(zonePrefix.count))
    }
}

// MARK: - Records and their values

nonisolated extension CKRecord {
    /// A record holding only the system fields saved by `encodedSystemFields`.
    static func decodingSystemFields(from data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    /// The record's system fields (its ID, type, change tag and so on), without its values.
    var encodedSystemFields: Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    // Encrypted values, by type. Setting nil removes the value.

    func setValue(_ value: String?, for key: String) {
        encryptedValues[key] = value
    }

    func setValue(_ value: Date?, for key: String) {
        encryptedValues[key] = value
    }

    func setValue(_ value: Decimal?, for key: String) {
        encryptedValues[key] = value.map { "\($0)" }
    }

    func setValue(_ value: Int?, for key: String) {
        encryptedValues[key] = value.map(Int64.init)
    }

    func setValue(_ value: Bool, for key: String) {
        encryptedValues[key] = Int64(value ? 1 : 0)
    }

    func string(_ key: String) -> String? {
        encryptedValues[key]
    }

    func date(_ key: String) -> Date? {
        encryptedValues[key]
    }

    /// Money, read back exactly as written whatever the device's locale.
    func decimal(_ key: String) -> Decimal? {
        let text: String? = encryptedValues[key]
        return text.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
    }

    func int(_ key: String) -> Int? {
        let value: Int64? = encryptedValues[key]
        return value.map(Int.init)
    }

    func bool(_ key: String) -> Bool? {
        int(key).map { $0 != 0 }
    }

    // References. Not encrypted: they only name another record in the same zone.

    func reference(_ key: String) -> CKRecord.Reference? {
        self[key] as? CKRecord.Reference
    }
}

extension CKRecord {
    /// Names `model`'s record, in this record's zone, or removes the reference for nil.
    func setReference(_ model: (some CloudRecordMapped)?, for key: String) {
        self[key] = model.map { CKRecord.Reference(recordID: CKRecord.ID(recordName: $0.syncID, zoneID: recordID.zoneID), action: .none) }
    }
}

// MARK: - Each model

extension Book {
    static let recordType: CKRecord.RecordType = "Book"

    func write(to record: CKRecord) {
        record.setValue(name, for: "name")
        record.setValue(createdAt, for: "createdAt")
    }

    func read(from record: CKRecord) {
        name = record.string("name") ?? name
        createdAt = record.date("createdAt") ?? createdAt
    }

    /// Every record in the book's zone: the book's own, then its models'. For a first upload.
    @MainActor
    func allRecords() -> [CKRecord] {
        let zoneID = zoneID
        var records = [makeRecord()]
        records += (categories ?? []).map { $0.makeRecord(in: zoneID) }
        records += (accounts ?? []).map { $0.makeRecord(in: zoneID) }
        records += (transactions ?? []).map { $0.makeRecord(in: zoneID) }
        records += (budgets ?? []).map { $0.makeRecord(in: zoneID) }
        records += (goals ?? []).map { $0.makeRecord(in: zoneID) }
        records += (recurringTransactions ?? []).map { $0.makeRecord(in: zoneID) }
        return records
    }

    /// The book's record in its zone.
    func makeRecord() -> CKRecord {
        let record = ckSystemFields.flatMap(CKRecord.decodingSystemFields(from:))
            ?? CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: syncID, zoneID: zoneID))
        write(to: record)
        return record
    }
}

extension Account: CloudRecordMapped {
    static let recordType: CKRecord.RecordType = "Account"

    func write(to record: CKRecord) {
        record.setValue(name, for: "name")
        record.setValue(initialBalance, for: "initialBalance")
        record.setValue(createdAt, for: "createdAt")
        record.setValue(iconName, for: "iconName")
    }

    func read(from record: CKRecord) {
        name = record.string("name") ?? ""
        initialBalance = record.decimal("initialBalance") ?? 0
        createdAt = record.date("createdAt") ?? createdAt
        iconName = record.string("iconName")
    }

    func readReferences(from _: CKRecord, resolver _: inout RecordResolver) {}
}

extension Category: CloudRecordMapped {
    static let recordType: CKRecord.RecordType = "Category"

    func write(to record: CKRecord) {
        record.setValue(name, for: "name")
        record.setValue(createdAt, for: "createdAt")
    }

    func read(from record: CKRecord) {
        name = record.string("name") ?? ""
        createdAt = record.date("createdAt") ?? createdAt
    }

    func readReferences(from _: CKRecord, resolver _: inout RecordResolver) {}
}

extension AccountTransaction: CloudRecordMapped {
    static let recordType: CKRecord.RecordType = "AccountTransaction"

    func write(to record: CKRecord) {
        record.setValue(date, for: "date")
        record.setValue(amount, for: "amount")
        record.setValue(payee, for: "payee")
        record.setValue(note, for: "note")
        record.setValue(isPosted, for: "isPosted")
        record.setValue(checkNumber, for: "checkNumber")
        record.setValue(kindRawValue, for: "kind")
        record.setReference(account, for: "account")
        record.setReference(category, for: "category")
        record.setReference(recurrence, for: "recurrence")
        // Only the outgoing half names the other; the incoming half's link is its inverse.
        record.setReference(incomingHalf, for: "incomingHalf")
    }

    func read(from record: CKRecord) {
        date = record.date("date") ?? date
        amount = record.decimal("amount") ?? 0
        payee = record.string("payee") ?? ""
        note = record.string("note") ?? ""
        isPosted = record.bool("isPosted") ?? false
        checkNumber = record.int("checkNumber")
        kindRawValue = record.string("kind") ?? TransactionKind.withdrawal.rawValue
    }

    func readReferences(from record: CKRecord, resolver: inout RecordResolver) {
        resolver.assign(record, "account", current: account) { account = $0 }
        resolver.assign(record, "category", current: category) { category = $0 }
        resolver.assign(record, "recurrence", current: recurrence) { recurrence = $0 }
        resolver.assign(record, "incomingHalf", current: incomingHalf) { incomingHalf = $0 }
    }
}

extension Budget: CloudRecordMapped {
    static let recordType: CKRecord.RecordType = "Budget"

    func write(to record: CKRecord) {
        record.setValue(name, for: "name")
        record.setValue(amount, for: "amount")
        record.setValue(periodRawValue, for: "period")
        record.setValue(startDate, for: "startDate")
        record.setValue(endDate, for: "endDate")
        record.setReference(category, for: "category")
    }

    func read(from record: CKRecord) {
        name = record.string("name") ?? ""
        amount = record.decimal("amount") ?? 0
        periodRawValue = record.string("period") ?? BudgetPeriod.monthly.rawValue
        startDate = record.date("startDate") ?? startDate
        endDate = record.date("endDate")
    }

    func readReferences(from record: CKRecord, resolver: inout RecordResolver) {
        resolver.assign(record, "category", current: category) { category = $0 }
    }
}

extension Goal: CloudRecordMapped {
    static let recordType: CKRecord.RecordType = "Goal"

    func write(to record: CKRecord) {
        record.setValue(name, for: "name")
        record.setValue(targetAmount, for: "targetAmount")
        record.setValue(initialBalance, for: "initialBalance")
        record.setValue(startDate, for: "startDate")
        record.setValue(targetDate, for: "targetDate")
        record.setReference(account, for: "account")
    }

    func read(from record: CKRecord) {
        name = record.string("name") ?? ""
        targetAmount = record.decimal("targetAmount") ?? 0
        initialBalance = record.decimal("initialBalance") ?? 0
        startDate = record.date("startDate") ?? startDate
        targetDate = record.date("targetDate") ?? targetDate
    }

    func readReferences(from record: CKRecord, resolver: inout RecordResolver) {
        resolver.assign(record, "account", current: account) { account = $0 }
    }
}

extension RecurringTransaction: CloudRecordMapped {
    static let recordType: CKRecord.RecordType = "RecurringTransaction"

    func write(to record: CKRecord) {
        record.setValue(kindRawValue, for: "kind")
        record.setValue(amount, for: "amount")
        record.setValue(payee, for: "payee")
        record.setValue(note, for: "note")
        record.setValue(createdAt, for: "createdAt")
        record.setValue(frequencyRawValue, for: "frequency")
        record.setValue(interval, for: "interval")
        record.setValue(startDate, for: "startDate")
        record.setValue(secondDay, for: "secondDay")
        record.setValue(endDate, for: "endDate")
        record.setValue(remainingCount, for: "remainingCount")
        record.setValue(nextDate, for: "nextDate")
        record.setReference(account, for: "account")
        record.setReference(otherAccount, for: "otherAccount")
        record.setReference(category, for: "category")
    }

    func read(from record: CKRecord) {
        kindRawValue = record.string("kind") ?? TransactionKind.withdrawal.rawValue
        amount = record.decimal("amount") ?? 0
        payee = record.string("payee") ?? ""
        note = record.string("note") ?? ""
        createdAt = record.date("createdAt") ?? createdAt
        frequencyRawValue = record.string("frequency") ?? RecurrenceFrequency.monthly.rawValue
        interval = record.int("interval") ?? 1
        startDate = record.date("startDate") ?? startDate
        secondDay = record.int("secondDay") ?? 15
        endDate = record.date("endDate")
        remainingCount = record.int("remainingCount")
        nextDate = record.date("nextDate") ?? nextDate
    }

    func readReferences(from record: CKRecord, resolver: inout RecordResolver) {
        resolver.assign(record, "account", current: account) { account = $0 }
        resolver.assign(record, "otherAccount", current: otherAccount) { otherAccount = $0 }
        resolver.assign(record, "category", current: category) { category = $0 }
    }
}
