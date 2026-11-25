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
