import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

/// Merging same-named categories, and what happens to the data when the iCloud account changes.
@MainActor
struct AccountAndMergeTests {
    // MARK: Merging categories

    @Test func mergesSameNamedCategoriesIntoTheOldest() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let book = Book(name: "Home")
        context.insert(book)
        let checking = Account(name: "Checking")
        context.insert(checking)
        checking.book = book

        // Two devices each made "Groceries"; this device's is newer.
        let older = Stirling_Money.Category(name: "Groceries")
        older.createdAt = day(2026, 1, 1)
        let newer = Stirling_Money.Category(name: " groceries ")
        newer.createdAt = day(2026, 2, 1)
        for category in [older, newer] {
            context.insert(category)
            category.book = book
        }
        let fromOlder = Ledger.addTransaction(.withdrawal, amount: 10, to: checking, payee: "A", category: older, in: context)
        let fromNewer = Ledger.addTransaction(.withdrawal, amount: 20, to: checking, payee: "B", category: newer, in: context)
        let budget = Budget(name: "Food", amount: 300)
        context.insert(budget)
        budget.book = book
        budget.category = newer
        var draft = RecurringDraft(account: checking, now: day(2026, 11, 1), calendar: utc)
        draft.payee = "Market"
        draft.amountText = "40"
        draft.category = newer
        let rule = try #require(draft.save(in: context, now: day(2026, 11, 1), calendar: utc))
        try context.save()

        #expect(try CategoryMerger.mergeDuplicates(in: context) == 1)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Stirling_Money.Category>()) == 1)
        #expect(fromOlder.category === older && fromNewer.category === older)
        #expect(budget.category === older, "the budget moves instead of being deleted with its category")
        #expect(rule.category === older)
    }

    @Test func booksKeepTheirOwnCategoriesOfTheSameName() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        for name in ["Home", "Personal"] {
            let book = Book(name: name)
            context.insert(book)
            _ = try Ledger.category(named: "Food", book: book, in: context)
        }
        #expect(try CategoryMerger.mergeDuplicates(in: context) == 0)
    }

    @Test func viewOnlyBooksAreLeftToTheirOwner() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let book = Book(name: "Parents")
        book.canEdit = false
        context.insert(book)
        for _ in 0 ..< 2 {
            let category = Stirling_Money.Category(name: "Gifts")
            context.insert(category)
            category.book = book
        }
        #expect(try CategoryMerger.mergeDuplicates(in: context) == 0)
    }

    @Test func everyDevicePicksTheSameKeeper() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let book = Book(name: "Home")
        context.insert(book)
        // Same time, same spelling: the syncID decides.
        let second = Stirling_Money.Category(name: "Food")
        second.syncID = "b"
        let first = Stirling_Money.Category(name: "Food")
        first.syncID = "a"
        for category in [second, first] {
            category.createdAt = day(2026, 1, 1)
            context.insert(category)
            category.book = book
        }
        try CategoryMerger.mergeDuplicates(in: context)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Stirling_Money.Category>()).map(\.syncID) == ["a"])
    }

    @Test func aFormHoldingAMergedCategorySavesTheSurvivor() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let book = Book(name: "Home")
        context.insert(book)
        let checking = Account(name: "Checking")
        context.insert(checking)
        checking.book = book
        let mine = try #require(try Ledger.category(named: "AAA", book: book, in: context))
        try context.save()

        // The form picks this device's new "AAA"…
        var draft = TransactionDraft(account: checking)
        draft.amountText = "1.50"
        draft.payee = "Test Sim"
        draft.category = mine

        // …while another device's older "AAA" arrives and the merge removes this one.
        let theirs = Stirling_Money.Category(name: "AAA")
        theirs.createdAt = mine.createdAt.addingTimeInterval(-60)
        context.insert(theirs)
        theirs.book = book
        try CategoryMerger.mergeDuplicates(in: context)
        try context.save()

        let saved = try #require(Ledger.save(draft, in: checking, context: context))
        #expect(saved.category === theirs, "not the deleted category, and not none")

        var budget = BudgetDraft()
        budget.name = "AAA"
        budget.amountText = "10"
        budget.category = mine
        #expect(budget.save(book: book, in: context)?.category === theirs)
    }

    @Test func twoDevicesMakingTheSameCategoryEndWithOne() throws {
        let server = FakeServer()
        let phone = try Device()
        let mac = try Device()
        let book = Book(name: "Home")
        phone.context.insert(book)
        let checking = Account(name: "Checking", initialBalance: 100)
        phone.context.insert(checking)
        checking.book = book
        try phone.context.save()
        try phone.send(to: server)
        try mac.fetch(from: server)

        // Each device makes "Food" before hearing from the other, with a purchase in it.
        for device in [phone, mac] {
            let account = try #require(try device.accounts().first)
            let food = try Ledger.category(named: "Food", book: account.book, in: device.context)
            Ledger.addTransaction(.withdrawal, amount: 5, to: account, payee: "Grocer", category: food, in: device.context)
            try device.context.save()
        }
        try phone.send(to: server)
        try mac.send(to: server)
        try phone.fetch(from: server)
        try mac.fetch(from: server)
        // The merges go up and come back.
        try phone.send(to: server)
        try mac.send(to: server)
        try phone.fetch(from: server)
        try mac.fetch(from: server)

        #expect(server.records(ofType: Stirling_Money.Category.recordType).count == 1)
        for device in [phone, mac] {
            let categories = try device.context.fetch(FetchDescriptor<Stirling_Money.Category>())
            #expect(categories.count == 1)
            #expect(categories.first?.transactions?.count == 2, "both purchases end up in the kept Food")
        }
    }

    // MARK: Account changes

    @Test func signingOutRemovesOnlyBooksOthersShared() throws {
        let device = try Device()
        let own = Book(name: "Personal")
        device.context.insert(own)
        try device.context.save()
        let ownersZone = CKRecordZone.ID(zoneName: Book.zonePrefix + "household", ownerName: "_owner")
        try device.processor.applyFetched([CKShare(recordZoneID: ownersZone)], deletions: [])
        _ = try device.processor.localChanges()

        try device.processor.removeSharedBooks()
        #expect(try device.context.fetch(FetchDescriptor<Book>()).map(\.name) == ["Personal"])
        #expect(try device.processor.localChanges().isEmpty, "removing them here isn't leaving")
    }

    @Test func aNewAccountStartsFromNoSyncState() throws {
        let server = FakeServer()
        let device = try Device()
        let book = Book(name: "Personal")
        device.context.insert(book)
        let checking = Account(name: "Checking")
        device.context.insert(checking)
        checking.book = book
        try device.context.save()
        try device.send(to: server)
        #expect(checking.ckSystemFields != nil && book.ckSystemFields != nil)

        try device.processor.forgetSyncState()
        #expect(checking.ckSystemFields == nil && checking.ckSyncedValues == nil)
        #expect(book.ckSystemFields == nil)
        #expect(try device.processor.localChanges().isEmpty, "forgetting isn't a change to send")
        // Uploading to the new account then sends everything as new records.
        #expect(try device.processor.allChanges().contains(.saveZone(book.zoneID)))
    }

    @Test func removingOwnBooksSendsNothing() throws {
        let device = try Device()
        let book = Book(name: "Personal")
        device.context.insert(book)
        try device.context.save()
        _ = try device.processor.localChanges()

        try device.processor.removeOwnBooks()
        #expect(try device.context.fetchCount(FetchDescriptor<Book>()) == 0)
        #expect(try device.processor.localChanges().isEmpty, "they stay in the old account's iCloud")
    }
}
