import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

/// A stand-in for CloudKit's private database: zones, records, and a log of changes for devices to fetch.
@MainActor
final class FakeServer {
    enum Event {
        case saved(CKRecord)
        case deleted(CKRecord.ID, CKRecord.RecordType)
        case zoneDeleted(CKRecordZone.ID)
    }

    private(set) var records: [CKRecord.ID: CKRecord] = [:]
    private(set) var zones: Set<CKRecordZone.ID> = []
    private(set) var log: [Event] = []

    func saveZone(_ zoneID: CKRecordZone.ID) {
        zones.insert(zoneID)
    }

    func save(_ record: CKRecord) {
        let copy = record.copy() as! CKRecord
        records[record.recordID] = copy
        log.append(.saved(copy))
    }

    func delete(_ recordID: CKRecord.ID) {
        guard let record = records.removeValue(forKey: recordID) else { return }
        log.append(.deleted(recordID, record.recordType))
    }

    func deleteZone(_ zoneID: CKRecordZone.ID) {
        zones.remove(zoneID)
        records = records.filter { $0.key.zoneID != zoneID }
        log.append(.zoneDeleted(zoneID))
    }

    func records(ofType type: CKRecord.RecordType) -> [CKRecord] {
        records.values.filter { $0.recordType == type }
    }
}

/// One device: its own store on disk (SwiftData keeps history only there) and its sync processor.
@MainActor
final class Device {
    let container: ModelContainer
    let processor: SyncProcessor
    private let folder: URL
    /// How far through the server's log this device has fetched.
    private var fetched = 0
    /// Saves a fetch asked for (merges made by sync), sent with the next `send`.
    private var queuedByFetch: [SyncProcessor.Change] = []

    var context: ModelContext {
        container.mainContext
    }

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: ModelConfiguration(url: folder.appending(path: "Device.store"), cloudKitDatabase: .none)
        )
        processor = SyncProcessor(context: container.mainContext)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Sends this device's changes, as the engine would: zones, then records built when asked, then the results.
    func send(to server: FakeServer) throws {
        try context.save()
        var queue = SyncProcessor.collapse(try processor.localChanges() + queuedByFetch)
        queuedByFetch = []
        while !queue.isEmpty {
            let changes = queue
            queue = []
            var saved: [CKRecord] = []
            for change in changes {
                switch change {
                case let .saveZone(zoneID): server.saveZone(zoneID)
                case let .deleteZone(zoneID): server.deleteZone(zoneID)
                case let .saveRecord(recordID):
                    if let record = try processor.record(for: recordID) {
                        server.save(record)
                        // As CloudKit may answer a save: the record's new system fields, without its values.
                        saved.append(CKRecord.decodingSystemFields(from: record.encodedSystemFields) ?? record)
                    }
                case let .deleteRecord(recordID): server.delete(recordID)
                case .cancelSave: break
                }
            }
            queue += try processor.didSave(saved)
        }
    }

    /// Queues changes for the next `send`, as the coordinator does at the end of a first sync.
    func queue(_ changes: [SyncProcessor.Change]) {
        queuedByFetch += changes
    }

    /// Fetches what changed on the server since the last fetch.
    func fetch(from server: FakeServer) throws {
        let events = server.log[fetched...]
        fetched = server.log.count
        var latest: [CKRecord.ID: CKRecord] = [:]
        var deletions: [(id: CKRecord.ID, type: CKRecord.RecordType)] = []
        var deletedZones: [CKRecordZone.ID] = []
        for event in events {
            switch event {
            case let .saved(record): latest[record.recordID] = record.copy() as? CKRecord
            case let .deleted(id, type):
                latest[id] = nil
                deletions.append((id, type))
            case let .zoneDeleted(zoneID): deletedZones.append(zoneID)
            }
        }
        queuedByFetch += try processor.applyFetched(Array(latest.values), deletions: deletions)
        for zoneID in deletedZones {
            try processor.applyDeletedZone(zoneID)
        }
    }

    func accounts() throws -> [Account] {
        try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)]))
    }
}

@MainActor
struct SyncTests {
    /// A book with Checking ($100), Savings, a categorized purchase and a transfer.
    @discardableResult
    private func addBook(to device: Device) throws -> Book {
        let context = device.context
        let book = Book(name: "Household")
        context.insert(book)
        let checking = Account(name: "Checking", initialBalance: 100)
        let savings = Account(name: "Savings")
        for account in [checking, savings] {
            context.insert(account)
            account.book = book
        }
        let food = try Ledger.category(named: "Food", book: book, in: context)
        Ledger.addTransaction(.withdrawal, amount: 30, to: checking, payee: "Grocer", category: food, in: context)
        Ledger.addTransfer(amount: 20, from: checking, to: savings, in: context)
        try context.save()
        return book
    }

    // MARK: Round trips

    @Test func aBookMadeOnOneDeviceAppearsOnAnother() throws {
        let server = FakeServer()
        let phone = try Device()
        let mac = try Device()
        let book = try addBook(to: phone)
        try phone.send(to: server)

        #expect(server.zones == [book.zoneID])
        #expect(server.records.count == 7, "the book, two accounts, a category, a purchase and two transfer halves")

        try mac.fetch(from: server)
        let books = try mac.context.fetch(FetchDescriptor<Book>())
        #expect(books.map(\.name) == ["Household"])
        #expect(books.first?.syncID == book.syncID)
        #expect(try mac.accounts().map(\.balance) == [50, 20])
        #expect(try mac.accounts().first?.transactions?.first { $0.kind == .withdrawal }?.category?.name == "Food")
    }

    @Test func whatSyncAppliesIsntSentBack() throws {
        let server = FakeServer()
        let phone = try Device()
        let mac = try Device()
        try addBook(to: phone)
        try phone.send(to: server)
        _ = try mac.processor.localChanges() // Nothing of the Mac's own yet.

        try mac.fetch(from: server)
        #expect(try mac.processor.localChanges().isEmpty)
        // Nor does the phone resend what the server accepted.
        #expect(try phone.processor.localChanges().isEmpty)
    }

    @Test func editsAndDeletesGoBothWays() throws {
        let server = FakeServer()
        let phone = try Device()
        let mac = try Device()
        try addBook(to: phone)
        try phone.send(to: server)
        try mac.fetch(from: server)

        // On the Mac: rename Savings and delete the purchase.
        let macChecking = try #require(try mac.accounts().first { $0.name == "Checking" })
        try #require(try mac.accounts().first { $0.name == "Savings" }).name = "Rainy Day"
        let purchase = try #require(macChecking.transactions?.first { $0.kind == .withdrawal })
        Ledger.delete(purchase, in: mac.context)
        try mac.send(to: server)

        try phone.fetch(from: server)
        #expect(try phone.accounts().map(\.name) == ["Checking", "Rainy Day"])
        #expect(try phone.accounts().first?.balance == 80)
    }

    @Test func deletingAnAccountDeletesItsTransactionsEverywhere() throws {
        let server = FakeServer()
        let phone = try Device()
        let mac = try Device()
        try addBook(to: phone)
        try phone.send(to: server)
        try mac.fetch(from: server)

        let checking = try #require(try phone.accounts().first { $0.name == "Checking" })
        phone.context.delete(checking)
        try phone.send(to: server)
        #expect(server.records(ofType: Account.recordType).count == 1)
        #expect(server.records(ofType: AccountTransaction.recordType).count == 1, "Savings keeps its half of the transfer")

        try mac.fetch(from: server)
        #expect(try mac.accounts().map(\.name) == ["Savings"])
        #expect(try mac.accounts().first?.balance == 20)
    }

    @Test func deletingABookDeletesItsZoneEverywhere() throws {
        let server = FakeServer()
        let phone = try Device()
        let mac = try Device()
        let book = try addBook(to: phone)
        try phone.send(to: server)
        try mac.fetch(from: server)

        phone.context.delete(book)
        try phone.send(to: server)
        #expect(server.zones.isEmpty)

        try mac.fetch(from: server)
        #expect(try mac.context.fetchCount(FetchDescriptor<Book>()) == 0)
        #expect(try mac.context.fetchCount(FetchDescriptor<Account>()) == 0)
    }

    @Test func somethingAddedAndDeletedBeforeSendingIsNeverSent() throws {
        let server = FakeServer()
        let phone = try Device()
        let book = try addBook(to: phone)
        try phone.send(to: server)

        let mistake = Account(name: "Mistake")
        phone.context.insert(mistake)
        mistake.book = book
        try phone.context.save()
        phone.context.delete(mistake)
        try phone.context.save()

        let changes = try phone.processor.localChanges()
        #expect(changes == [.cancelSave(recordName: mistake.syncID)])
    }

    @Test func aRecordDeletedWhileItsSaveWasOnTheWayIsDeletedAfter() throws {
        let phone = try Device()
        let book = try addBook(to: phone)
        let account = try #require(book.accounts?.first)
        let record = account.makeRecord(in: book.zoneID)
        phone.context.delete(account)
        try phone.context.save()

        #expect(try phone.processor.didSave([record]) == [.deleteRecord(record.recordID)])
    }

    // MARK: Recurring transactions on two devices

    @Test func twoDevicesAddingTheSameOccurrenceKeepOne() throws {
        let server = FakeServer()
        let phone = try Device()
        let mac = try Device()
        let book = try addBook(to: phone)
        let checking = try #require(book.accounts?.first { $0.name == "Checking" })
        var draft = RecurringDraft(account: checking, now: day(2026, 11, 1), calendar: utc)
        draft.payee = "Rent"
        draft.amountText = "40"
        _ = try #require(draft.save(in: phone.context, now: day(2026, 11, 1), calendar: utc))
        try phone.send(to: server)
        try mac.fetch(from: server)

        // Both devices add November's rent before hearing from the other.
        try RecurringScheduler.addDue(in: phone.context, now: day(2026, 11, 2), calendar: utc)
        try RecurringScheduler.addDue(in: mac.context, now: day(2026, 11, 2), calendar: utc)
        try phone.send(to: server)
        try mac.send(to: server)
        try phone.fetch(from: server)
        try mac.fetch(from: server)

        let rent = server.records(ofType: AccountTransaction.recordType).filter { $0.string("payee") == "Rent" }
        #expect(rent.count == 1)
        for device in [phone, mac] {
            let rentHere = try device.context.fetch(FetchDescriptor<AccountTransaction>()).filter { $0.payee == "Rent" }
            #expect(rentHere.count == 1)
            #expect(try device.accounts().first?.balance == 10)
        }
    }

    // MARK: Refused saves

    /// A transaction synced to the server, with the server's copy changed by another device.
    private func conflict(
        editHere: (AccountTransaction) -> Void,
        editThere: (CKRecord) -> Void
    ) throws -> (device: Device, transaction: AccountTransaction, changes: [SyncProcessor.Change]) {
        let server = FakeServer()
        let phone = try Device()
        try addBook(to: phone)
        try phone.send(to: server)
        let transaction = try #require(try phone.context.fetch(FetchDescriptor<AccountTransaction>()).first { $0.kind == .withdrawal })

        let zoneID = try #require(transaction.book?.zoneID)
        let serverCopy = try #require(server.records[CKRecord.ID(recordName: transaction.syncID, zoneID: zoneID)])
        let theirs = try #require(serverCopy.copy() as? CKRecord)
        editThere(theirs)
        editHere(transaction)
        try phone.context.save()

        let attempt = transaction.makeRecord(in: transaction.book!.zoneID)
        let error = CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: theirs])
        let changes = try phone.processor.didFail(attempt, error: error)
        return (phone, transaction, changes)
    }

    @Test func aConflictKeepsEachSidesChanges() throws {
        let (device, transaction, changes) = try conflict(
            editHere: { $0.payee = "Corner Grocer" },
            editThere: { $0.setValue("Weekly shop", for: "note") }
        )
        #expect(transaction.payee == "Corner Grocer")
        #expect(transaction.note == "Weekly shop")
        #expect(changes.count == 1, "the merged record goes up again")
        withExtendedLifetime(device) {}
    }

    @Test func aConflictOverTheSameFieldKeepsThisDevicesEdit() throws {
        let (device, transaction, _) = try conflict(
            editHere: { $0.amount = -35 },
            editThere: { $0.setValue(Decimal(-32), for: "amount") }
        )
        #expect(transaction.amount == -35)
        withExtendedLifetime(device) {}
    }

    @Test func postedWinsWhenBothSidesChangeIt() throws {
        let (device, transaction, _) = try conflict(
            editHere: { $0.isPosted = false; $0.note = "x" },
            editThere: { $0.setValue(true, for: "isPosted") }
        )
        // Only the server changed it (it was false), so the server's value stands anyway.
        #expect(transaction.isPosted)
        withExtendedLifetime(device) {}

        // Un-posting here alone is kept: the server still has the value both last agreed on.
        let unposted = CKRecord(recordType: AccountTransaction.recordType)
        unposted.setValue(false, for: "isPosted")
        let posted = CKRecord(recordType: AccountTransaction.recordType)
        posted.setValue(true, for: "isPosted")
        let agreed = RecordMerger.values(of: posted)
        #expect(RecordMerger.merge(local: unposted, server: posted.copy() as! CKRecord, ancestor: agreed).bool("isPosted") == false)

        // Both changed it from what they agreed on: posted wins.
        #expect(RecordMerger.merge(local: unposted, server: posted.copy() as! CKRecord, ancestor: ["isPosted": "n:2"]).bool("isPosted") == true)
    }

    /// Your scenario 3: the phone edits offline, the Mac edits the same transaction and sends first, and the phone
    /// fetches the Mac's copy before sending its own.
    @Test func anEditNotYetSentSurvivesFetchingAnotherDevicesEdit() throws {
        let server = FakeServer()
        let phone = try Device()
        let mac = try Device()
        try addBook(to: phone)
        try phone.send(to: server)
        try mac.fetch(from: server)

        func purchase(on device: Device) throws -> AccountTransaction {
            try #require(try device.context.fetch(FetchDescriptor<AccountTransaction>()).first { $0.kind == .withdrawal })
        }

        // Offline on the phone: a new payee, saved but not sent.
        try purchase(on: phone).payee = "Corner Grocer"
        try phone.context.save()

        // On the Mac: a note, sent first.
        try purchase(on: mac).note = "Weekly shop"
        try mac.send(to: server)

        // Back online, the phone fetches before it sends.
        try phone.fetch(from: server)
        #expect(try purchase(on: phone).payee == "Corner Grocer", "the unsent edit isn't overwritten")
        #expect(try purchase(on: phone).note == "Weekly shop")

        try phone.send(to: server)
        try mac.fetch(from: server)
        #expect(try purchase(on: mac).payee == "Corner Grocer")
        #expect(try purchase(on: mac).note == "Weekly shop")
    }

    @Test func aMergeMadeWhileFetchingIsSentBack() throws {
        let server = FakeServer()
        let phone = try Device()
        let mac = try Device()
        try addBook(to: phone)
        try phone.send(to: server)
        try mac.fetch(from: server)

        let phonePurchase = try #require(try phone.context.fetch(FetchDescriptor<AccountTransaction>()).first { $0.kind == .withdrawal })
        phonePurchase.payee = "Corner Grocer"
        try phone.context.save()
        let macPurchase = try #require(try mac.context.fetch(FetchDescriptor<AccountTransaction>()).first { $0.kind == .withdrawal })
        macPurchase.note = "Weekly shop"
        try mac.send(to: server)

        let zoneID = try #require(phonePurchase.book?.zoneID)
        let recordID = CKRecord.ID(recordName: phonePurchase.syncID, zoneID: zoneID)
        let fetched = try #require(server.records[recordID]?.copy() as? CKRecord)
        let changes = try phone.processor.applyFetched([fetched], deletions: [])
        #expect(changes == [.saveRecord(recordID)])
    }

    @Test func aFetchedEditIsAppliedWhenNothingIsUnsent() throws {
        let server = FakeServer()
        let phone = try Device()
        let mac = try Device()
        try addBook(to: phone)
        try phone.send(to: server)
        try mac.fetch(from: server)

        let macPurchase = try #require(try mac.context.fetch(FetchDescriptor<AccountTransaction>()).first { $0.kind == .withdrawal })
        macPurchase.payee = "Market"
        try mac.send(to: server)
        try phone.fetch(from: server)

        let purchase = try #require(try phone.context.fetch(FetchDescriptor<AccountTransaction>()).first { $0.kind == .withdrawal })
        #expect(purchase.payee == "Market")
        #expect(try phone.processor.localChanges().isEmpty, "nothing of the phone's own to send")
    }

    @Test func anEmptyAncestorFromAnOlderBuildMeansUnknown() throws {
        #expect(RecordMerger.decode(RecordMerger.encode([:])) == nil)

        // A record synced by an older build, then edited on the Mac: the phone takes the Mac's edit.
        let server = FakeServer()
        let phone = try Device()
        let mac = try Device()
        try addBook(to: phone)
        try phone.send(to: server)
        try mac.fetch(from: server)
        let phonePurchase = try #require(try phone.context.fetch(FetchDescriptor<AccountTransaction>()).first { $0.kind == .withdrawal })
        phonePurchase.ckSyncedValues = RecordMerger.encode([:])
        try phone.context.save()
        _ = try phone.processor.localChanges()

        let macPurchase = try #require(try mac.context.fetch(FetchDescriptor<AccountTransaction>()).first { $0.kind == .withdrawal })
        macPurchase.note = "Weekly shop"
        try mac.send(to: server)
        try phone.fetch(from: server)
        #expect(phonePurchase.note == "Weekly shop")
    }

    @Test func datesMatchToTheMillisecond() {
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000.123_4)
        let local = CKRecord(recordType: "AccountTransaction")
        local.setValue(date, for: "date")
        let server = CKRecord(recordType: "AccountTransaction")
        server.setValue(Date(timeIntervalSinceReferenceDate: 800_000_000.123), for: "date")
        #expect(RecordMerger.values(of: local) == RecordMerger.values(of: server))
    }

    @Test func aRecurringRulesLaterNextDateWins() {
        let local = CKRecord(recordType: RecurringTransaction.recordType)
        local.setValue(day(2026, 12, 1), for: "nextDate")
        local.setValue(10, for: "remainingCount")
        local.setValue("Rent", for: "payee")
        let server = CKRecord(recordType: RecurringTransaction.recordType)
        server.setValue(day(2027, 1, 1), for: "nextDate")
        server.setValue(9, for: "remainingCount")
        server.setValue("Rent", for: "payee")

        let merged = RecordMerger.merge(local: local, server: server, ancestor: nil)
        #expect(merged.date("nextDate") == day(2027, 1, 1))
        #expect(merged.int("remainingCount") == 9)
    }

    @Test func aRecordDeletedElsewhereIsDeletedHere() throws {
        let server = FakeServer()
        let phone = try Device()
        try addBook(to: phone)
        try phone.send(to: server)
        let savings = try #require(try phone.accounts().first { $0.name == "Savings" })
        savings.name = "Edited"
        try phone.context.save()

        let record = try savings.makeRecord(in: #require(savings.book?.zoneID))
        _ = try phone.processor.didFail(record, error: CKError(.unknownItem))
        #expect(try phone.accounts().map(\.name) == ["Checking"])
    }

    @Test func aMissingZoneIsMadeForANewBookButMeansDeletedForASyncedOne() throws {
        let phone = try Device()
        let book = try addBook(to: phone)
        let account = try #require(book.accounts?.first)
        let record = account.makeRecord(in: book.zoneID)

        let retry = try phone.processor.didFail(record, error: CKError(.zoneNotFound))
        #expect(retry == [.saveZone(book.zoneID), .saveRecord(record.recordID)])

        book.remember(book.makeRecord())
        try phone.context.save()
        #expect(try phone.processor.didFail(record, error: CKError(.zoneNotFound)).isEmpty)
        #expect(try phone.context.fetchCount(FetchDescriptor<Book>()) == 0)
    }

    @Test func collapsingKeepsTheLastChangeAndPutsZonesFirst() {
        let zone = CKRecordZone.ID(zoneName: "Book-a")
        let id = CKRecord.ID(recordName: "x", zoneID: zone)
        let changes = SyncProcessor.collapse([.saveRecord(id), .saveZone(zone), .deleteRecord(id)])
        #expect(changes == [.saveZone(zone), .deleteRecord(id)])
    }
}
