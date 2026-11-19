import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

/// Recurring transactions in the widget summary (`upcoming`) and the summary as of a later day
/// (`projected(on:)`), in a fixed UTC calendar.
@MainActor
struct WidgetProjectionTests {
    private typealias Occurrence = WidgetSnapshot.UpcomingOccurrence

    /// Checking $1,000 and Savings $500; a goal on Savings from $500 to $1,500; a Groceries budget and an all-spending
    /// budget for November.
    private func summary(upcoming: [Occurrence]) -> WidgetSnapshot {
        WidgetSnapshot(
            accounts: [
                .init(id: "checking", name: "Checking", balance: 1000, postedBalance: 1000),
                .init(id: "savings", name: "Savings", balance: 500, postedBalance: 500),
            ],
            goals: [
                .init(
                    id: "trip", name: "Trip", accountName: "Savings", currentAmount: 500, targetAmount: 1500,
                    progress: 0, targetDate: day(2027, 6, 1), accountID: "savings", initialBalance: 500
                ),
            ],
            budgets: [
                .init(id: "food", name: "Food", categoryName: "Groceries", amount: 400, spent: 100,
                      periodStart: day(2026, 11, 1), periodEnd: day(2026, 12, 1)),
                .init(id: "all", name: "Everything", categoryName: nil, amount: 2000, spent: 300,
                      periodStart: day(2026, 11, 1), periodEnd: day(2026, 12, 1)),
            ],
            upcoming: upcoming,
            updatedAt: day(2026, 11, 19)
        )
    }

    // MARK: Projecting

    @Test func dueOccurrencesChangeTheBalanceNotThePostedBalance() {
        let snapshot = summary(upcoming: [
            Occurrence(date: day(2026, 11, 20), accountID: "checking", amount: -50, categoryName: "Groceries"),
            Occurrence(date: day(2026, 11, 25), accountID: "checking", amount: -200),
        ])

        let friday = snapshot.projected(on: day(2026, 11, 20).addingTimeInterval(8 * 3600), calendar: utc)
        #expect(friday.accounts[0].balance == 950)
        #expect(friday.accounts[0].postedBalance == 1000, "they arrive unposted")
        #expect(friday.total == 1450)
        #expect(friday.upcoming.count == 1, "the one due is no longer upcoming")

        let later = snapshot.projected(on: day(2026, 11, 26), calendar: utc)
        #expect(later.accounts[0].balance == 750)
        #expect(later.upcoming.isEmpty)
        #expect(later.projected(on: day(2026, 11, 26), calendar: utc) == later, "projecting again changes nothing")
    }

    @Test func nothingDueLeavesTheSummaryAlone() {
        let snapshot = summary(upcoming: [Occurrence(date: day(2026, 12, 1), accountID: "checking", amount: -50)])
        #expect(snapshot.projected(on: day(2026, 11, 30), calendar: utc) == snapshot)
    }

    @Test func transfersMoveMoneyWithoutChangingTheTotal() {
        let snapshot = summary(upcoming: [
            Occurrence(date: day(2026, 11, 20), accountID: "checking", amount: -200, otherAccountID: "savings", isTransfer: true),
        ])
        let projected = snapshot.projected(on: day(2026, 11, 20), calendar: utc)
        #expect(projected.accounts.map(\.balance) == [800, 700])
        #expect(projected.total == snapshot.total)
    }

    @Test func goalsOnTheAccountMoveAndTheirProgressFollows() {
        let snapshot = summary(upcoming: [
            Occurrence(date: day(2026, 11, 20), accountID: "checking", amount: -250, otherAccountID: "savings", isTransfer: true),
        ])
        let goal = snapshot.projected(on: day(2026, 11, 20), calendar: utc).goals[0]
        #expect(goal.currentAmount == 750)
        #expect(goal.progress == 0.25, "a quarter of the way from $500 to $1,500")
    }

    @Test func goalsFromOlderSummariesWithoutTheirAccountStayPut() {
        var snapshot = summary(upcoming: [Occurrence(date: day(2026, 11, 20), accountID: "savings", amount: 300)])
        snapshot.goals[0].accountID = nil
        #expect(snapshot.projected(on: day(2026, 11, 20), calendar: utc).goals[0].currentAmount == 500)
    }

    @Test func budgetsCountByTheSameRulesAsTheApp() {
        let snapshot = summary(upcoming: [
            // Groceries spending: counts in both budgets.
            Occurrence(date: day(2026, 11, 20), accountID: "checking", amount: -50, categoryName: "Groceries"),
            // A Groceries refund: lowers Food's spending, but income isn't negative spending for Everything.
            Occurrence(date: day(2026, 11, 21), accountID: "checking", amount: 20, categoryName: "Groceries"),
            // Rent: only Everything.
            Occurrence(date: day(2026, 11, 22), accountID: "checking", amount: -900, categoryName: "Housing"),
            // A transfer: never.
            Occurrence(date: day(2026, 11, 23), accountID: "checking", amount: -100, otherAccountID: "savings", isTransfer: true),
            // Next period: not this one.
            Occurrence(date: day(2026, 12, 1), accountID: "checking", amount: -75, categoryName: "Groceries"),
        ])
        let budgets = snapshot.projected(on: day(2026, 12, 1), calendar: utc).budgets
        #expect(budgets[0].spent == 130, "100 + 50 - 20")
        #expect(budgets[1].spent == 1250, "300 + 50 + 900")
    }

    @Test func upcomingDaysAreTheDistinctDaysAfterToday() {
        let snapshot = summary(upcoming: [
            Occurrence(date: day(2026, 11, 19), accountID: "checking", amount: -1),
            Occurrence(date: day(2026, 11, 20), accountID: "checking", amount: -1),
            Occurrence(date: day(2026, 11, 20), accountID: "savings", amount: 1),
            Occurrence(date: day(2026, 12, 25), accountID: "checking", amount: -1),
            Occurrence(date: day(2027, 3, 1), accountID: "checking", amount: -1),
        ])
        #expect(snapshot.upcomingDays(after: day(2026, 11, 19), within: 45, calendar: utc) == [day(2026, 11, 20), day(2026, 12, 25)])
    }

    @Test func widgetsRedrawNowOnEachDueDayAndAtExtraMoments() {
        let now = day(2026, 11, 19).addingTimeInterval(10 * 3600)
        let snapshot = summary(upcoming: [
            Occurrence(date: day(2026, 11, 20), accountID: "checking", amount: -1),
            Occurrence(date: day(2026, 11, 25), accountID: "checking", amount: -1),
        ])
        // A budget period ending Dec 1, and one extra moment already past (ignored).
        #expect(snapshot.timelineDates(now: now, adding: [day(2026, 12, 1), day(2026, 11, 1)], calendar: utc)
            == [now, day(2026, 11, 20), day(2026, 11, 25), day(2026, 12, 1)])
        #expect(summary(upcoming: []).timelineDates(now: now, calendar: utc) == [now], "nothing due: just now")
        // The same day twice is one entry.
        #expect(snapshot.timelineDates(now: now, adding: [day(2026, 11, 20)], calendar: utc).count == 3)
    }

    // MARK: Building the summary

    @Test func theSummaryListsTheNext45DaysOfOccurrences() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking", initialBalance: 1000)
        let savings = Account(name: "Savings")
        context.insert(checking)
        context.insert(savings)
        let groceries = try #require(try Ledger.category(named: "Groceries", in: context))

        let weekly = RecurringTransaction(kind: .withdrawal, amount: 60, payee: "Market", frequency: .weekly, startDate: day(2026, 11, 20), calendar: utc)
        let saving = RecurringTransaction(kind: .transfer, amount: 200, frequency: .monthly, startDate: day(2026, 12, 1), calendar: utc)
        let twice = RecurringTransaction(kind: .deposit, amount: 10, payee: "Rebate", frequency: .weekly, startDate: day(2026, 11, 21), remainingCount: 2, calendar: utc)
        let broken = RecurringTransaction(kind: .transfer, amount: 5, frequency: .weekly, startDate: day(2026, 11, 20), calendar: utc)
        [weekly, saving, twice, broken].forEach(context.insert)
        weekly.account = checking
        weekly.category = groceries
        saving.account = checking
        saving.otherAccount = savings
        twice.account = checking
        broken.account = checking // No account to transfer to: needs attention, so not listed.
        try context.save()

        let snapshot = WidgetSnapshot(
            accounts: [checking, savings], goals: [], recurring: [weekly, saving, twice, broken],
            now: day(2026, 11, 19), calendar: utc
        )

        // Through Jan 3: seven Fridays from Nov 20, Dec 1 for the transfer, and two rebates.
        #expect(snapshot.upcoming.filter { $0.amount == -60 }.count == 7)
        #expect(snapshot.upcoming.filter { $0.amount == 10 }.count == 2, "the count limits it")
        #expect(snapshot.upcoming.allSatisfy { $0.amount != -5 })
        #expect(snapshot.upcoming.map(\.date) == snapshot.upcoming.map(\.date).sorted())

        let market = try #require(snapshot.upcoming.first)
        #expect(market.date == day(2026, 11, 20))
        #expect(market.categoryName == "Groceries")
        #expect(market.accountID == WidgetSnapshot.widgetID(for: checking))

        let transfer = try #require(snapshot.upcoming.first { $0.isTransfer })
        #expect(transfer.otherAccountID == WidgetSnapshot.widgetID(for: savings))
        #expect(transfer.categoryName == nil)
    }

    @Test func projectingMatchesWhatTheAppAddsLater() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking", initialBalance: 3000)
        let savings = Account(name: "Savings", initialBalance: 500)
        context.insert(checking)
        context.insert(savings)
        let groceries = try #require(try Ledger.category(named: "Groceries", in: context))
        Ledger.addTransaction(.withdrawal, amount: 120, to: checking, date: day(2026, 11, 5), payee: "Market", category: groceries, in: context)

        let food = Budget(name: "Food", amount: 400, startDate: day(2026, 1, 1))
        let everything = Budget(name: "Everything", amount: 3000, startDate: day(2026, 1, 1))
        let goal = Goal(name: "Trip", targetAmount: 1500, targetDate: day(2027, 6, 1), initialBalance: 500, startDate: day(2026, 11, 1))
        let market = RecurringTransaction(kind: .withdrawal, amount: 60, payee: "Market", frequency: .weekly, startDate: day(2026, 11, 20), calendar: utc)
        let saving = RecurringTransaction(kind: .transfer, amount: 250, frequency: .monthly, startDate: day(2026, 11, 25), calendar: utc)
        context.insert(food)
        context.insert(everything)
        context.insert(goal)
        context.insert(market)
        context.insert(saving)
        food.category = groceries
        goal.account = savings
        market.account = checking
        market.category = groceries
        saving.account = checking
        saving.otherAccount = savings
        try context.save()

        func snapshot(on date: Date) throws -> WidgetSnapshot {
            try WidgetSnapshot(
                accounts: [checking, savings], goals: [goal], budgets: [food, everything],
                transactions: context.fetch(FetchDescriptor<AccountTransaction>()),
                recurring: [market, saving], now: date, calendar: utc
            )
        }

        let projected = try snapshot(on: day(2026, 11, 19)).projected(on: day(2026, 11, 28), calendar: utc)
        try RecurringScheduler.addDue(in: context, now: day(2026, 11, 28), calendar: utc)
        let actual = try snapshot(on: day(2026, 11, 28))

        #expect(projected.accounts.map(\.balance) == actual.accounts.map(\.balance))
        #expect(projected.accounts.map(\.postedBalance) == actual.accounts.map(\.postedBalance))
        #expect(projected.goals.map(\.currentAmount) == actual.goals.map(\.currentAmount))
        #expect(projected.goals.map(\.progress) == actual.goals.map(\.progress))
        #expect(projected.budgets.map(\.spent) == actual.budgets.map(\.spent))
        #expect(projected.budgets.map(\.spent) == [240, 240], "120 + two Fridays of 60; the transfer doesn't count")
    }

    // MARK: Older summaries

    @Test func summariesFromBeforeRecurringTransactionsStillDecode() throws {
        let json = #"""
        {"accounts":[{"id":"a","name":"Checking","balance":10,"postedBalance":10}],
         "goals":[{"id":"g","name":"Trip","accountName":"Checking","currentAmount":10,"targetAmount":100,"progress":0.1,"targetDate":0}],
         "updatedAt":0}
        """#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.upcoming.isEmpty)
        #expect(snapshot.goals[0].accountID == nil)
        #expect(snapshot.goals[0].initialBalance == nil)
        #expect(snapshot.projected(on: .now) == snapshot)
    }

    @Test func summariesWithUpcomingSurviveJSON() throws {
        let snapshot = summary(upcoming: [
            Occurrence(date: day(2026, 11, 20), accountID: "checking", amount: -200, otherAccountID: "savings", isTransfer: true),
        ])
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }
}
