import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

@MainActor
struct BudgetAndGoalTests {
    private let november = DateInterval(start: day(2026, 11, 1), end: day(2026, 12, 1))

    /// Checking has: groceries -50 and +5 refund in November, groceries -20 in October,
    /// dining -30 in November, a paycheck +1000 in November, and a 200 transfer out in November.
    private func makeLedger(in context: ModelContext) throws -> (all: [AccountTransaction], groceries: Stirling_Money.Category) {
        let checking = Account(name: "Checking")
        let savings = Account(name: "Savings")
        context.insert(checking)
        context.insert(savings)
        let groceries = try #require(try Ledger.category(named: "Groceries", in: context))
        let dining = try Ledger.category(named: "Dining", in: context)

        Ledger.addTransaction(.withdrawal, amount: 50, to: checking, date: day(2026, 11, 3), payee: "Grocer", category: groceries, in: context)
        Ledger.addTransaction(.deposit, amount: 5, to: checking, date: day(2026, 11, 4), payee: "Grocer refund", category: groceries, in: context)
        Ledger.addTransaction(.withdrawal, amount: 20, to: checking, date: day(2026, 10, 28), payee: "Grocer", category: groceries, in: context)
        Ledger.addTransaction(.check, amount: 30, to: checking, date: day(2026, 11, 10), payee: "Diner", checkNumber: 1, category: dining, in: context)
        Ledger.addTransaction(.deposit, amount: 1000, to: checking, date: day(2026, 11, 15), payee: "Employer", in: context)
        Ledger.addTransfer(amount: 200, from: checking, to: savings, date: day(2026, 11, 16), in: context)

        return try (context.fetch(FetchDescriptor<AccountTransaction>()), groceries)
    }

    @Test func categoryBudgetCountsNetSpendingInPeriod() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let (_, groceries) = try makeLedger(in: context)
        let budget = Budget(name: "Food", amount: 300)
        context.insert(budget)
        budget.category = groceries

        #expect(budget.spent(during: november, from: groceries.transactions ?? []) == 45)
    }

    @Test func allSpendingBudgetIgnoresIncomeAndTransfers() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let (all, _) = try makeLedger(in: context)
        let budget = Budget(name: "Everything", amount: 2000)
        context.insert(budget)

        #expect(budget.spent(during: november, from: all) == 80)
    }

    @Test func recurringBudgetStopsAfterEndDate() {
        let budget = Budget(name: "Food", amount: 300, startDate: day(2026, 1, 1), endDate: day(2026, 6, 30))
        #expect(!budget.isActive(on: day(2025, 12, 31), calendar: utc))
        #expect(budget.isActive(on: day(2026, 6, 30), calendar: utc))
        #expect(!budget.isActive(on: day(2026, 7, 1), calendar: utc))
    }

    @Test func goalProgressIsMeasuredFromStartingBalance() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let savings = Account(name: "Savings", initialBalance: 200)
        context.insert(savings)
        let goal = Goal(name: "Trip", targetAmount: 1000, targetDate: day(2026, 12, 25), initialBalance: savings.balance)
        context.insert(goal)
        goal.account = savings

        Ledger.addTransaction(.deposit, amount: 300, to: savings, payee: "Paycheck", in: context)

        #expect(goal.currentAmount == 500)
        #expect(goal.amountRemaining == 500)
        #expect(goal.progress == 0.375)

        Ledger.addTransaction(.deposit, amount: 900, to: savings, payee: "Bonus", in: context)
        #expect(goal.amountRemaining == 0)
        #expect(goal.progress == 1)
    }

    @Test func goalDaysRemainingGoesNegativeWhenOverdue() {
        let goal = Goal(name: "Trip", targetAmount: 1000, targetDate: day(2026, 12, 25), initialBalance: 0)
        #expect(goal.daysRemaining(from: day(2026, 12, 20), calendar: utc) == 5)
        #expect(goal.daysRemaining(from: day(2026, 12, 25), calendar: utc) == 0)
        #expect(goal.daysRemaining(from: day(2026, 12, 27), calendar: utc) == -2)
    }
}
