import CloudKit
import Foundation

/// Merges this device's copy of a record with the server's when CloudKit refuses a save because someone else changed
/// it first (`serverRecordChanged`).
///
/// It compares each field with the values both sides last agreed on (`ancestor`, saved after each sync):
/// - Changed on only one side: that side's value.
/// - Changed on both: this device's, as the later edit, except:
///   - `isPosted`: posted wins, since a bank never un-clears a transaction.
///   - A recurring rule's `nextDate`: the later date (with that side's `remainingCount`), so no occurrence is
///     added twice.
/// - With no ancestor (never synced from here), this device's values win, with the same exceptions.
///
/// Balances aren't stored, so they never need merging. Deletes win over edits; the sync engine handles those.
enum RecordMerger {
    /// A record's values as text, by field: what `ancestor` is made of. References are the record name they point to.
    nonisolated static func values(of record: CKRecord) -> [String: String] {
        var values: [String: String] = [:]
        let encrypted = record.encryptedValues.allKeys()
        for key in encrypted {
            values[key] = text(record.encryptedValues[key])
        }
        // `allKeys()` lists the encrypted keys too, which read as nil here.
        for key in record.allKeys() where !encrypted.contains(key) {
            values[key] = text(record[key])
        }
        return values
    }

    nonisolated static func encode(_ values: [String: String]) -> Data? {
        try? JSONEncoder().encode(values)
    }

    nonisolated static func decode(_ data: Data?) -> [String: String]? {
        data.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
    }

    /// The server's record with the merged values written into it, ready to save again.
    static func merge(local: CKRecord, server: CKRecord, ancestor: [String: String]?) -> CKRecord {
        let mine = values(of: local)
        let theirs = values(of: server)
        let keys = Set(mine.keys).union(theirs.keys)

        // A rule's next date and remaining count move together, so they come from the same side.
        var nextDateFromServer: Bool?
        if server.recordType == RecurringTransaction.recordType,
           let localNext = local.date("nextDate"), let serverNext = server.date("nextDate"), localNext != serverNext
        {
            nextDateFromServer = serverNext > localNext
        }

        for key in keys where mine[key] != theirs[key] {
            let fromServer: Bool
            if key == "nextDate" || key == "remainingCount", let nextDateFromServer {
                fromServer = nextDateFromServer
            } else if let ancestor, mine[key] == ancestor[key] {
                // Only the server changed it.
                fromServer = true
            } else if let ancestor, theirs[key] == ancestor[key] {
                // Only this device changed it.
                fromServer = false
            } else if key == "isPosted" {
                // Both changed it (or there's no ancestor): posted wins.
                fromServer = server.bool(key) == true
            } else {
                fromServer = false
            }
            if !fromServer {
                copy(key, from: local, to: server)
            }
        }
        return server
    }

    /// Copies one field, by its type: the untyped subscript doesn't reliably set an encrypted value.
    private static func copy(_ key: String, from source: CKRecord, to target: CKRecord) {
        let isEncrypted = source.encryptedValues.allKeys().contains(key) || target.encryptedValues.allKeys().contains(key)
        guard isEncrypted else {
            target[key] = source[key]
            return
        }
        let values = source.encryptedValues
        if let value: String = values[key] {
            target.encryptedValues[key] = value
        } else if let value: Date = values[key] {
            target.encryptedValues[key] = value
        } else if let value: Int64 = values[key] {
            target.encryptedValues[key] = value
        } else if let value: Double = values[key] {
            target.encryptedValues[key] = value
        } else if let value: Data = values[key] {
            target.encryptedValues[key] = value
        } else {
            target.encryptedValues[key] = nil as String?
        }
    }

    private nonisolated static func text(_ value: Any?) -> String? {
        switch value {
        case nil: nil
        case let string as String: "s:" + string
        case let date as Date: "d:\(date.timeIntervalSinceReferenceDate)"
        case let number as NSNumber: "n:\(number)"
        case let reference as CKRecord.Reference: "r:" + reference.recordID.recordName
        case let data as Data: "b:" + data.base64EncodedString()
        default: "?:\(String(describing: value))"
        }
    }
}
