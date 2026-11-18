import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Stirling_Money

/// When the app rewrites the widget summary (`WidgetSnapshot.needsWrite(over:)`): only when something other than
/// the time changed, so the widgets aren't reloaded and the Watch isn't sent the same figures again.
@MainActor
struct WidgetSnapshotWriteTests {
    /// One set of models (so IDs stay the same between summaries), with amounts that aren't round numbers.
    private let container: ModelContainer
    private let account: Account
    private let goal: Goal
    private let budget: Budget

    init() throws {
        container = try makeInMemoryContainer()
        let context = container.mainContext
        account = Account(name: "Checking")
        context.insert(account)
        Ledger.addTransaction(.deposit, amount: Decimal(string: "1234.56")!, to: account, date: day(2026, 11, 1), payee: "Pay", in: context)
        Ledger.addTransaction(.withdrawal, amount: Decimal(string: "82.14")!, to: account, date: day(2026, 11, 3), payee: "Grocer", in: context)
        budget = Budget(name: "Everything", amount: Decimal(string: "333.33")!, startDate: day(2026, 1, 1))
        context.insert(budget)
        goal = Goal(name: "Trip", targetAmount: Decimal(string: "999.99")!, targetDate: day(2027, 3, 1), initialBalance: 0, startDate: day(2026, 1, 1))
        context.insert(goal)
        goal.account = account
        try context.save()
    }

    /// The summary as the app builds it.
    private func summary(now: Date = day(2026, 11, 20), accent: Color.Resolved? = nil) throws -> WidgetSnapshot {
        try WidgetSnapshot(
            accounts: [account], goals: [goal], budgets: [budget],
            transactions: container.mainContext.fetch(FetchDescriptor<AccountTransaction>()),
            accentColor: accent, now: now, calendar: utc
        )
    }

    @Test func writesWhenThereIsNoFileOrItCantBeRead() throws {
        let snapshot = try summary()
        #expect(snapshot.needsWrite(over: nil))
        #expect(snapshot.needsWrite(over: Data("not a summary".utf8)))
    }

    @Test func skipsTheSameFiguresWrittenEarlier() throws {
        let saved = try JSONEncoder().encode(summary(now: day(2026, 11, 20)))
        let later = try summary(now: day(2026, 11, 20).addingTimeInterval(3600))
        #expect(!later.needsWrite(over: saved), "only the time differs")
    }

    @Test func skipsTheSameFiguresWithACustomAccentColor() throws {
        // The color's Floats don't come back from JSON exactly; that mustn't count as a change.
        let accent = Color.Resolved(red: 0.123_456_7, green: 0.765_432_1, blue: 0.333_333_3)
        let saved = try JSONEncoder().encode(summary(accent: accent))
        let again = try summary(now: day(2026, 11, 20).addingTimeInterval(60), accent: accent)
        #expect(!again.needsWrite(over: saved))
    }

    @Test func writesWhenABalanceChanges() throws {
        let saved = try JSONEncoder().encode(summary())
        try Ledger.addTransaction(.withdrawal, amount: #require(Decimal(string: "0.01")), to: account, date: day(2026, 11, 5), payee: "Fee", in: container.mainContext)
        #expect(try summary().needsWrite(over: saved))
    }

    @Test func writesWhenTheAccentColorChanges() throws {
        let saved = try JSONEncoder().encode(summary())
        #expect(try summary(accent: Color.Resolved(red: 0.5, green: 0.2, blue: 0.8)).needsWrite(over: saved))
    }

    @Test func writesWhenAGoalIsRenamed() throws {
        let saved = try JSONEncoder().encode(summary())
        goal.name = "Holiday"
        #expect(try summary().needsWrite(over: saved))
    }

    @Test func writesWhenABudgetPeriodRollsOver() throws {
        let saved = try JSONEncoder().encode(summary(now: day(2026, 11, 20)))
        let december = try summary(now: day(2026, 12, 2))
        #expect(december.budgets.first?.periodStart == day(2026, 12, 1))
        #expect(december.needsWrite(over: saved))
    }
}
