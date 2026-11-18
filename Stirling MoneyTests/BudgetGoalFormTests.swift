import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

@MainActor
struct BudgetGoalFormTests {
    // MARK: Budget summary

    @Test func summaryReportsCurrentPeriodSpending() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking")
        context.insert(checking)
        let groceries = try #require(try Ledger.category(named: "Groceries", in: context))
        Ledger.addTransaction(.withdrawal, amount: 300, to: checking, date: day(2026, 11, 3), payee: "Grocer", category: groceries, in: context)
        Ledger.addTransaction(.withdrawal, amount: 150, to: checking, date: day(2026, 11, 20), payee: "Grocer", category: groceries, in: context)
        Ledger.addTransaction(.withdrawal, amount: 999, to: checking, date: day(2026, 10, 20), payee: "Grocer", category: groceries, in: context)

        let budget = Budget(name: "Food", amount: 400, startDate: day(2026, 1, 1))
        context.insert(budget)
        budget.category = groceries

        let summary = budget.summary(on: day(2026, 11, 25), allTransactions: [], calendar: utc)
        #expect(summary.state == .active(DateInterval(start: day(2026, 11, 1), end: day(2026, 12, 1))))
        #expect(summary.spent == 450)
        #expect(summary.remaining == -50)
        #expect(summary.isOverBudget)
        #expect(summary.progress == 1)
    }

    @Test func allSpendingSummaryUsesEveryTransaction() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking")
        context.insert(checking)
        Ledger.addTransaction(.withdrawal, amount: 100, to: checking, date: day(2026, 11, 3), payee: "Shop", in: context)
        Ledger.addTransaction(.deposit, amount: 1000, to: checking, date: day(2026, 11, 4), payee: "Employer", in: context)
        let all = try context.fetch(FetchDescriptor<AccountTransaction>())

        let budget = Budget(name: "Everything", amount: 400, startDate: day(2026, 1, 1))
        context.insert(budget)

        let summary = budget.summary(on: day(2026, 11, 25), allTransactions: all, calendar: utc)
        #expect(summary.spent == 100)
        #expect(summary.remaining == 300)
        #expect(summary.progress == 0.25)
    }

    @Test func summaryBeforeStartAndAfterEnd() throws {
        let container = try makeInMemoryContainer()
        let budget = Budget(name: "Trip", amount: 500, period: .custom, startDate: day(2026, 6, 1), endDate: day(2026, 6, 14))
        container.mainContext.insert(budget)

        #expect(budget.summary(on: day(2026, 5, 31), allTransactions: [], calendar: utc).state == .notStarted)
        #expect(budget.summary(on: day(2026, 6, 15), allTransactions: [], calendar: utc).state == .ended)
        #expect(
            budget.summary(on: day(2026, 6, 14), allTransactions: [], calendar: utc).state
                == .active(DateInterval(start: day(2026, 6, 1), end: day(2026, 6, 15)))
        )
    }

    @Test func recurringPeriodIsCutShortAtEndDate() throws {
        let container = try makeInMemoryContainer()
        let budget = Budget(name: "Food", amount: 400, startDate: day(2026, 1, 1), endDate: day(2026, 11, 10))
        container.mainContext.insert(budget)

        let summary = budget.summary(on: day(2026, 11, 5), allTransactions: [], calendar: utc)
        #expect(summary.state == .active(DateInterval(start: day(2026, 11, 1), end: day(2026, 11, 11))))
    }

    // MARK: Budget form

    @Test func newBudgetDraftStartsOnFirstOfMonth() {
        let draft = BudgetDraft(now: day(2026, 11, 17), calendar: utc)
        #expect(draft.startDate == day(2026, 11, 1))
        #expect(draft.endDate == day(2026, 11, 30))
        #expect(draft.period == .monthly)
        #expect(draft.effectiveEndDate == nil)
    }

    @Test func budgetValidation() {
        var draft = BudgetDraft(now: day(2026, 11, 17), calendar: utc)
        #expect(!draft.isValid)
        draft.name = "Food"
        draft.amountText = "0"
        #expect(!draft.isValid)
        #expect(draft.hasInvalidAmount)
        draft.amountText = "400"
        #expect(draft.isValid)

        draft.period = .custom
        #expect(draft.effectiveEndDate == day(2026, 11, 30), "custom budgets always have an end date")
        draft.endDate = day(2026, 10, 1)
        #expect(draft.hasEndBeforeStart(calendar: utc))

        // A recurring budget without "Ends" turned on ignores the end date.
        draft.period = .monthly
        #expect(!draft.hasEndBeforeStart(calendar: utc))
    }

    @Test func savingBudgetCreatesThenUpdates() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let groceries = try Ledger.category(named: "Groceries", in: context)

        var draft = BudgetDraft(now: day(2026, 11, 17), calendar: utc)
        draft.name = "  Food "
        draft.amountText = "$400.00"
        draft.category = groceries
        let budget = try #require(draft.save(in: context))
        #expect(budget.name == "Food")
        #expect(budget.amount == 400)
        #expect(budget.endDate == nil)
        #expect(groceries?.budgets?.count == 1)

        var edit = BudgetDraft(editing: budget, calendar: utc)
        #expect(edit.amount == 400)
        edit.category = nil
        edit.period = .weekly
        edit.hasEndDate = true
        edit.endDate = day(2027, 1, 31)
        edit.save(editing: budget, in: context)

        #expect(budget.category == nil)
        #expect(budget.period == .weekly)
        #expect(budget.endDate == day(2027, 1, 31))
        #expect(try context.fetchCount(FetchDescriptor<Budget>()) == 1)
    }

    // MARK: Goal form

    @Test func newGoalStartsFromAccountBalance() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let savings = Account(name: "Savings", initialBalance: 2000)
        context.insert(savings)

        var draft = GoalDraft(now: day(2026, 11, 17), calendar: utc)
        #expect(draft.targetDate == day(2027, 11, 17))
        draft.name = "Car"
        draft.targetText = "5000"
        #expect(!draft.isValid, "an account is required")
        draft.account = savings
        let goal = try #require(draft.save(in: context, now: day(2026, 11, 17)))

        #expect(goal.initialBalance == 2000)
        #expect(goal.startDate == day(2026, 11, 17))
        #expect(goal.account === savings)
        #expect(goal.progress == 0)
    }

    @Test func movingGoalToAnotherAccountRestartsProgress() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let savings = Account(name: "Savings", initialBalance: 2000)
        let brokerage = Account(name: "Brokerage", initialBalance: 7000)
        context.insert(savings)
        context.insert(brokerage)
        let goal = Goal(name: "Car", targetAmount: 5000, targetDate: day(2027, 6, 1), initialBalance: 1000, startDate: day(2026, 1, 1))
        context.insert(goal)
        goal.account = savings

        // Renaming keeps the starting point.
        var draft = GoalDraft(editing: goal)
        draft.name = "New Car"
        draft.save(editing: goal, in: context, now: day(2026, 11, 17))
        #expect(goal.initialBalance == 1000)
        #expect(goal.startDate == day(2026, 1, 1))

        draft.account = brokerage
        draft.targetText = "10000"
        draft.save(editing: goal, in: context, now: day(2026, 11, 17))
        #expect(goal.name == "New Car")
        #expect(goal.targetAmount == 10000)
        #expect(goal.initialBalance == 7000)
        #expect(goal.startDate == day(2026, 11, 17))
        #expect(goal.account === brokerage)
    }

    @Test func positiveUserInputRejectsZeroAndDropsSign() {
        #expect(Decimal(positiveUserInput: "-12.50") == Decimal(string: "12.50"))
        #expect(Decimal(positiveUserInput: "0") == nil)
        #expect(Decimal(positiveUserInput: "") == nil)
        #expect(Decimal(positiveUserInput: "abc") == nil)
    }

    @Test func goalTargetIsInvalidOnlyWhenSomethingUnusableIsTyped() {
        var draft = GoalDraft(now: day(2026, 11, 17), calendar: utc)
        #expect(!draft.hasInvalidTarget, "nothing typed yet isn't an error")
        draft.targetText = "abc"
        #expect(draft.hasInvalidTarget)
        draft.targetText = "0"
        #expect(draft.hasInvalidTarget)
        draft.targetText = "-500"
        #expect(!draft.hasInvalidTarget, "a typed minus sign is dropped")
        #expect(draft.target == 500)
        draft.targetText = "5000"
        #expect(!draft.hasInvalidTarget)
    }

    @Test func editingABudgetWithAnEndDateFillsTheForm() throws {
        let budget = Budget(name: "Trip", amount: 600, period: .custom, startDate: day(2026, 6, 1), endDate: day(2026, 6, 30))
        let draft = BudgetDraft(editing: budget, calendar: utc)
        #expect(draft.name == "Trip")
        #expect(Decimal(userInput: draft.amountText) == 600, "the amount is shown as currency and parses back")
        #expect(draft.period == .custom)
        #expect(draft.startDate == day(2026, 6, 1))
        #expect(draft.hasEndDate)
        #expect(draft.endDate == day(2026, 6, 30))
        #expect(draft.effectiveEndDate == day(2026, 6, 30))
    }

    @Test func editingABudgetWithoutAnEndDateLeavesItOff() {
        let budget = Budget(name: "Food", amount: 400, period: .weekly, startDate: day(2026, 3, 2))
        let draft = BudgetDraft(editing: budget, calendar: utc)
        #expect(draft.period == .weekly)
        #expect(draft.startDate == day(2026, 3, 2))
        #expect(!draft.hasEndDate)
        #expect(draft.effectiveEndDate == nil)
    }
}
