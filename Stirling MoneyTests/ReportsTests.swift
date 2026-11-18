import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

@MainActor
struct ReportsTests {
    @Test func monthsEndWithTheCurrentMonth() {
        let months = Reports.months(count: 3, endingAt: day(2026, 1, 15), calendar: utc)
        #expect(months == [day(2025, 11, 1), day(2025, 12, 1), day(2026, 1, 1)])

        let range = Reports.monthRange(count: 3, endingAt: day(2026, 1, 15), calendar: utc)
        #expect(range == DateInterval(start: day(2025, 11, 1), end: day(2026, 2, 1)))
    }

    @Test func incomeAndExpensesLeaveOutTransfers() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking")
        let savings = Account(name: "Savings")
        context.insert(checking)
        context.insert(savings)
        Ledger.addTransaction(.deposit, amount: 1000, to: checking, date: day(2026, 10, 1), payee: "Employer", in: context)
        Ledger.addTransaction(.withdrawal, amount: 300, to: checking, date: day(2026, 10, 5), payee: "Shop", in: context)
        Ledger.addTransaction(.withdrawal, amount: 50, to: checking, date: day(2026, 11, 2), payee: "Shop", in: context)
        Ledger.addTransfer(amount: 200, from: checking, to: savings, date: day(2026, 10, 9), in: context)
        // Outside the range.
        Ledger.addTransaction(.deposit, amount: 999, to: checking, date: day(2026, 8, 31), payee: "Old", in: context)
        let all = try context.fetch(FetchDescriptor<AccountTransaction>())

        let totals = Reports.incomeAndExpenses(all, months: 3, endingAt: day(2026, 11, 20), calendar: utc)

        #expect(totals == [
            MonthTotal(month: day(2026, 9, 1), income: 0, expenses: 0),
            MonthTotal(month: day(2026, 10, 1), income: 1000, expenses: 300),
            MonthTotal(month: day(2026, 11, 1), income: 0, expenses: 50),
        ])
        #expect(totals[1].net == 700)
    }

    @Test func spendingByCategoryFoldsSmallCategoriesIntoOther() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking")
        context.insert(checking)
        // Categories A...I spending 90, 80, ... 10, all in November.
        for (index, name) in ["A", "B", "C", "D", "E", "F", "G", "H", "I"].enumerated() {
            let category = try Ledger.category(named: name, in: context)
            Ledger.addTransaction(.withdrawal, amount: Decimal(90 - index * 10), to: checking, date: day(2026, 11, 3), payee: "Shop", category: category, in: context)
        }
        Ledger.addTransaction(.withdrawal, amount: 35, to: checking, date: day(2026, 11, 4), payee: "Cash", in: context)
        let all = try context.fetch(FetchDescriptor<AccountTransaction>())

        let slices = Reports.spendingByCategory(all, in: DateInterval(start: day(2026, 11, 1), end: day(2026, 12, 1)))

        #expect(slices.map(\.categoryName) == ["A", "B", "C", "D", "E", "F", nil, nil])
        #expect(slices.map(\.amount) == [90, 80, 70, 60, 50, 40, 35, 60], "uncategorized (35) is its own slice; G, H and I fold into Other, which comes last")
        #expect(slices[6].colorSlot == 6, "uncategorized ranks 7th")
        #expect(slices.last?.isOther == true)
        #expect(slices.count <= 8, "never more slices than palette colors")
    }

    @Test func categoryColorsDontChangeWithTheRange() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking")
        context.insert(checking)
        let rent = try Ledger.category(named: "Rent", in: context)
        let food = try Ledger.category(named: "Food", in: context)
        Ledger.addTransaction(.withdrawal, amount: 1000, to: checking, date: day(2026, 10, 1), payee: "Landlord", category: rent, in: context)
        Ledger.addTransaction(.withdrawal, amount: 100, to: checking, date: day(2026, 11, 1), payee: "Grocer", category: food, in: context)
        let all = try context.fetch(FetchDescriptor<AccountTransaction>())

        // November alone has only Food, but Food keeps the slot it has overall.
        let november = Reports.spendingByCategory(all, in: DateInterval(start: day(2026, 11, 1), end: day(2026, 12, 1)))
        #expect(november == [CategorySlice(categoryName: "Food", amount: 100, colorSlot: 1)])
    }

    @Test func refundsReduceCategorySpending() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking")
        context.insert(checking)
        let food = try #require(try Ledger.category(named: "Food", in: context))
        Ledger.addTransaction(.withdrawal, amount: 100, to: checking, date: day(2026, 11, 1), payee: "Grocer", category: food, in: context)
        Ledger.addTransaction(.deposit, amount: 30, to: checking, date: day(2026, 11, 2), payee: "Refund", category: food, in: context)
        Ledger.addTransaction(.deposit, amount: 50, to: checking, date: day(2026, 10, 2), payee: "Refund", category: food, in: context)

        let months = Reports.spending(in: food, months: 2, endingAt: day(2026, 11, 20), calendar: utc)
        #expect(months == [
            MonthAmount(month: day(2026, 10, 1), amount: -50),
            MonthAmount(month: day(2026, 11, 1), amount: 70),
        ])
    }

    @Test func budgetHistoryStopsAtTheBudgetStart() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking")
        context.insert(checking)
        let food = try #require(try Ledger.category(named: "Food", in: context))
        Ledger.addTransaction(.withdrawal, amount: 120, to: checking, date: day(2026, 10, 10), payee: "Grocer", category: food, in: context)
        Ledger.addTransaction(.withdrawal, amount: 80, to: checking, date: day(2026, 11, 10), payee: "Grocer", category: food, in: context)
        let budget = Budget(name: "Food", amount: 100, startDate: day(2026, 9, 1))
        context.insert(budget)
        budget.category = food

        let history = Reports.history(of: budget, allTransactions: [], on: day(2026, 11, 20), calendar: utc)

        #expect(history.map(\.interval.start) == [day(2026, 9, 1), day(2026, 10, 1), day(2026, 11, 1)])
        #expect(history.map(\.spent) == [0, 120, 80])
    }

    @Test func budgetHistoryOfEndedBudgetShowsItsLastPeriods() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let budget = Budget(name: "Food", amount: 100, period: .weekly, startDate: day(2026, 1, 1), endDate: day(2026, 3, 4))
        context.insert(budget)

        let history = Reports.history(of: budget, allTransactions: [], periods: 2, on: day(2026, 11, 20), calendar: utc)

        // Weeks run Thursday to Thursday from Jan 1; the last is cut short after the Mar 4 end date.
        #expect(history.map(\.interval) == [
            DateInterval(start: day(2026, 2, 19), end: day(2026, 2, 26)),
            DateInterval(start: day(2026, 2, 26), end: day(2026, 3, 5)),
        ])
    }

    @Test func customBudgetHistoryIsOnePeriod() throws {
        let container = try makeInMemoryContainer()
        let budget = Budget(name: "Trip", amount: 500, period: .custom, startDate: day(2026, 6, 1), endDate: day(2026, 6, 14))
        container.mainContext.insert(budget)

        let history = Reports.history(of: budget, allTransactions: [], on: day(2026, 11, 20), calendar: utc)
        #expect(history.map(\.interval) == [DateInterval(start: day(2026, 6, 1), end: day(2026, 6, 15))])
        #expect(Reports.history(of: budget, allTransactions: [], on: day(2026, 5, 1), calendar: utc).isEmpty)
    }

    @Test func categoriesThatSpendTheSameAreOrderedByName() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking")
        context.insert(checking)
        for name in ["Beta", "alpha", "Gamma"] {
            let category = try Ledger.category(named: name, in: context)
            Ledger.addTransaction(.withdrawal, amount: 50, to: checking, date: day(2026, 11, 3), payee: "Shop", category: category, in: context)
        }
        let all = try context.fetch(FetchDescriptor<AccountTransaction>())

        let slices = Reports.spendingByCategory(all, in: DateInterval(start: day(2026, 11, 1), end: day(2026, 12, 1)))

        // Ties are broken by name, ignoring case, so the colors don't depend on the order things were entered.
        #expect(slices.map(\.categoryName) == ["alpha", "Beta", "Gamma"])
        #expect(slices.map(\.colorSlot) == [0, 1, 2])
    }
}
