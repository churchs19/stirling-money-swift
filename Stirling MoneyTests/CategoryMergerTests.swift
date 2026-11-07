import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

@MainActor
struct CategoryMergerTests {
    @Test func mergesSameNamedCategoriesIntoTheOldest() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking")
        context.insert(checking)

        // Two devices each created "Groceries"; this device's is newer.
        let older = Stirling_Money.Category(name: "Groceries")
        older.createdAt = day(2026, 1, 1)
        let newer = Stirling_Money.Category(name: " groceries ")
        newer.createdAt = day(2026, 2, 1)
        let dining = Stirling_Money.Category(name: "Dining")
        [older, newer, dining].forEach(context.insert)

        let fromOlder = Ledger.addTransaction(.withdrawal, amount: 10, to: checking, payee: "A", category: older, in: context)
        let fromNewer = Ledger.addTransaction(.withdrawal, amount: 20, to: checking, payee: "B", category: newer, in: context)
        let budget = Budget(name: "Food", amount: 300)
        context.insert(budget)
        budget.category = newer
        try context.save()

        let merged = try CategoryMerger.mergeDuplicates(in: context)

        #expect(merged == 1)
        #expect(try context.fetchCount(FetchDescriptor<Stirling_Money.Category>()) == 2)
        #expect(fromOlder.category === older)
        #expect(fromNewer.category === older)
        #expect(budget.category === older, "the budget moves instead of being deleted with its category")
        #expect(try context.fetchCount(FetchDescriptor<Budget>()) == 1)
        #expect(older.name == "Groceries")
    }

    @Test func doesNothingWithoutDuplicates() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        _ = try Ledger.category(named: "Groceries", in: context)
        _ = try Ledger.category(named: "Dining", in: context)

        #expect(try CategoryMerger.mergeDuplicates(in: context) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Stirling_Money.Category>()) == 2)
    }

    @Test func sameCreationTimeStillPicksTheSameKeeper() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let lower = Stirling_Money.Category(name: "groceries")
        let upper = Stirling_Money.Category(name: "Groceries")
        lower.createdAt = day(2026, 1, 1)
        upper.createdAt = day(2026, 1, 1)
        context.insert(lower)
        context.insert(upper)

        try CategoryMerger.mergeDuplicates(in: context)

        // "G" sorts before "g", whatever order the fetch returned them in.
        let remaining = try context.fetch(FetchDescriptor<Stirling_Money.Category>())
        #expect(remaining.map(\.name) == ["Groceries"])
    }
}
