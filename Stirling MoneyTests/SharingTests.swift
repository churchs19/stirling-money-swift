import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

/// Books shared with other people: the processor's side of it, with no network. (Inviting, accepting and the
/// shared engine itself need two Apple IDs.)
@MainActor
struct SharingTests {
    /// A zone in someone else's database, as it appears in the user's shared database.
    private let ownersZone = CKRecordZone.ID(zoneName: Book.zonePrefix + "household", ownerName: "_owner")

    @Test func zonesOwnedBySomeoneElseAreShared() {
        #expect(SyncProcessor.isSharedWithUser(ownersZone))
        #expect(!SyncProcessor.isSharedWithUser(CKRecordZone.ID(zoneName: Book.zonePrefix + "mine")))
        #expect(SyncProcessor.shareID(in: ownersZone).recordName == CKRecordNameZoneWideShare)
        #expect(SyncProcessor.shareID(in: ownersZone).zoneID == ownersZone)
    }

    @Test func anAcceptedBookArrivesAsSomeoneElses() throws {
        let device = try Device()
        let share = CKShare(recordZoneID: ownersZone)
        let bookRecord = CKRecord(recordType: Book.recordType, recordID: CKRecord.ID(recordName: "household", zoneID: ownersZone))
        bookRecord.setValue("Household", for: "name")

        try device.processor.applyFetched([share, bookRecord], deletions: [])

        let book = try #require(try device.context.fetch(FetchDescriptor<Book>()).first)
        #expect(book.name == "Household")
        #expect(book.syncID == "household")
        #expect(book.zoneOwnerName == "_owner")
        #expect(book.zoneID == ownersZone)
        #expect(book.isShared)
        #expect(!book.isOwnedByMe)
        #expect(book.ownerName == nil, "a share without the owner's name leaves it unknown, not empty")
        // Applying the share is sync's own doing: nothing to send back.
        #expect(try device.processor.localChanges().isEmpty)
    }

    @Test func leavingABookDeletesTheShareNotTheZone() throws {
        let device = try Device()
        try device.processor.applyFetched([CKShare(recordZoneID: ownersZone)], deletions: [])
        let book = try #require(try device.context.fetch(FetchDescriptor<Book>()).first)
        _ = try device.processor.localChanges()

        device.context.delete(book)
        try device.context.save()

        #expect(try device.processor.localChanges() == [.deleteRecord(SyncProcessor.shareID(in: ownersZone))])
    }

    @Test func leavingABookWithRecordsSendsOnlyTheLeave() throws {
        let device = try Device()
        let checking = CKRecord(recordType: Account.recordType, recordID: CKRecord.ID(recordName: "checking", zoneID: ownersZone))
        checking.setValue("Checking", for: "name")
        let purchase = CKRecord(recordType: AccountTransaction.recordType, recordID: CKRecord.ID(recordName: "purchase", zoneID: ownersZone))
        purchase.setValue(Decimal(-5), for: "amount")
        purchase["account"] = CKRecord.Reference(recordID: checking.recordID, action: .none)
        try device.processor.applyFetched([CKShare(recordZoneID: ownersZone), checking, purchase], deletions: [])
        let book = try #require(try device.context.fetch(FetchDescriptor<Book>()).first)
        #expect(book.accounts?.count == 1)
        _ = try device.processor.localChanges()

        // Deleting the book deletes its account and transaction here too; none of that may reach the owner's zone.
        device.context.delete(book)
        try device.context.save()
        #expect(try device.context.fetchCount(FetchDescriptor<AccountTransaction>()) == 0)
        #expect(try device.processor.localChanges() == [.deleteRecord(SyncProcessor.shareID(in: ownersZone))])
    }

    @Test func deletingAnOwnBookWithRecordsSendsOnlyTheZone() throws {
        let device = try Device()
        let book = Book(name: "Personal")
        device.context.insert(book)
        let checking = Account(name: "Checking")
        device.context.insert(checking)
        checking.book = book
        Ledger.addTransaction(.withdrawal, amount: 5, to: checking, payee: "Cafe", in: device.context)
        try device.context.save()
        _ = try device.processor.localChanges()

        device.context.delete(book)
        try device.context.save()
        let changes = try device.processor.localChanges()
        #expect(changes.contains(.deleteZone(book.zoneID)))
        // Never-synced records only cancel their pending saves; nothing is sent for them.
        #expect(!changes.contains { change in
            if case .deleteRecord = change { true } else if case .saveRecord = change { true } else { false }
        })
    }

    @Test func deletingAnOwnBookStillDeletesItsZone() throws {
        let device = try Device()
        let book = Book(name: "Personal")
        device.context.insert(book)
        try device.context.save()
        _ = try device.processor.localChanges()

        device.context.delete(book)
        try device.context.save()
        #expect(try device.processor.localChanges() == [.deleteZone(book.zoneID)])
    }

    @Test func onlyTheUsersOwnBooksAreUploadedOnTheFirstRun() throws {
        let device = try Device()
        let own = Book(name: "Personal")
        device.context.insert(own)
        try device.processor.applyFetched([CKShare(recordZoneID: ownersZone)], deletions: [])

        let zones = try device.processor.allChanges().compactMap { change -> CKRecordZone.ID? in
            if case let .saveZone(zoneID) = change {
                zoneID
            } else {
                nil
            }
        }
        #expect(zones == [own.zoneID])
    }

    @Test func sharingStateAloneIsntSent() throws {
        let device = try Device()
        let book = Book(name: "Personal")
        device.context.insert(book)
        try device.context.save()
        _ = try device.processor.localChanges()

        book.isShared = true
        book.ownerName = "Pat"
        try device.context.save()
        #expect(try device.processor.localChanges().isEmpty)
    }

    @Test func sharingAndStoppingMarkTheOwnersBook() throws {
        let device = try Device()
        let book = Book(name: "Personal")
        device.context.insert(book)
        try device.context.save()
        _ = try device.processor.localChanges()

        try device.processor.didShare(book, with: CKShare(recordZoneID: book.zoneID))
        #expect(book.isShared && book.isOwnedByMe && book.canEdit)

        // Stopping on another of the owner's devices arrives as the share's deletion.
        try device.processor.applyFetched(
            [], deletions: [(id: SyncProcessor.shareID(in: book.zoneID), type: CKRecord.SystemType.share)]
        )
        #expect(!book.isShared)
        #expect(try device.context.fetchCount(FetchDescriptor<Book>()) == 1, "the owner keeps the book")
        #expect(try device.processor.localChanges().isEmpty)
    }

    @Test func aStoppedShareRemovesTheBookForEveryoneElse() throws {
        let device = try Device()
        try device.processor.applyFetched([CKShare(recordZoneID: ownersZone)], deletions: [])
        #expect(try device.context.fetchCount(FetchDescriptor<Book>()) == 1)

        // The owner stopped sharing: the zone leaves this user's shared database.
        try device.processor.applyDeletedZone(ownersZone)
        #expect(try device.context.fetchCount(FetchDescriptor<Book>()) == 0)
        #expect(try device.processor.localChanges().isEmpty, "removing it isn't sent as leaving")
    }
}
