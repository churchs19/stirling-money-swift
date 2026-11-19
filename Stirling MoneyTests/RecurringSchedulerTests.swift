import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

/// Adding recurring transactions when they fall due (`RecurringScheduler`), in a fixed UTC calendar.
@MainActor
struct RecurringSchedulerTests {
    private let container: ModelContainer
    private var context: ModelContext {
        container.mainContext
    }

    private let checking = Account(name: "Checking", initialBalance: 3000)
    private let savings = Account(name: "Savings", initialBalance: 500)

    init() throws {
        container = try makeInMemoryContainer()
        container.mainContext.insert(checking)
        container.mainContext.insert(savings)
    }

    private func rule(
        _ kind: TransactionKind = .withdrawal,
        amount: Decimal = 100,
        payee: String = "Gym",
        frequency: RecurrenceFrequency = .monthly,
        interval: Int = 1,
        start: Date = day(2026, 11, 1),
        endDate: Date? = nil,
        remainingCount: Int? = nil,
        to destination: Account? = nil
    ) -> RecurringTransaction {
        let rule = RecurringTransaction(
            kind: kind, amount: amount, payee: payee, note: "Auto", frequency: frequency, interval: interval,
            startDate: start, endDate: endDate, remainingCount: remainingCount, calendar: utc
        )
        context.insert(rule)
        rule.account = checking
        rule.otherAccount = destination
        return rule
    }

    private func addDue(on date: Date) throws -> Int {
        try RecurringScheduler.addDue(in: context, now: date, calendar: utc)
    }

    private var transactions: [AccountTransaction] {
        get throws {
            try context.fetch(FetchDescriptor<AccountTransaction>(sortBy: [SortDescriptor(\.date)]))
        }
    }

    // MARK: Adding what's due

    @Test func addsAnOccurrenceThatIsDueAsAnUnpostedTransaction() throws {
        let groceries = try #require(try Ledger.category(named: "Groceries", in: context))
        let gym = rule()
        gym.category = groceries

        #expect(try addDue(on: day(2026, 11, 20)) == 1)

        let added = try #require(try transactions.first)
        #expect(added.date == day(2026, 11, 1))
        #expect(added.amount == -100)
        #expect(added.payee == "Gym")
        #expect(added.note == "Auto")
        #expect(added.category === groceries)
        #expect(!added.isPosted)
        #expect(added.recurrence === gym)
        #expect(gym.nextDate == day(2026, 12, 1))
        #expect(checking.balance == 2900)
        #expect(checking.postedBalance == 3000, "it arrives unposted")
    }

    @Test func nothingIsAddedBeforeTheStart() throws {
        let gym = rule(start: day(2026, 12, 1))
        #expect(try addDue(on: day(2026, 11, 30)) == 0)
        #expect(try transactions.isEmpty)
        #expect(gym.nextDate == day(2026, 12, 1))
    }

    @Test func anOccurrenceIsDueAllDayIncludingLateAtNight() throws {
        _ = rule(start: day(2026, 11, 20))
        #expect(try addDue(on: day(2026, 11, 20).addingTimeInterval(23 * 3600 + 59 * 60)) == 1)
    }

    @Test func missedOccurrencesAreAllAddedOnTheirOwnDates() throws {
        let gym = rule()
        #expect(try addDue(on: day(2027, 2, 15)) == 4)
        #expect(try transactions.map(\.date) == [day(2026, 11, 1), day(2026, 12, 1), day(2027, 1, 1), day(2027, 2, 1)])
        #expect(gym.nextDate == day(2027, 3, 1))
        #expect(checking.balance == 2600)
    }

    @Test func runningAgainAddsNothingNew() throws {
        _ = rule()
        #expect(try addDue(on: day(2026, 12, 10)) == 2)
        #expect(try addDue(on: day(2026, 12, 10)) == 0)
        #expect(try addDue(on: day(2026, 12, 31)) == 0)
        #expect(try transactions.count == 2)
    }

    @Test func stopsAfterTheEndDate() throws {
        let gym = rule(endDate: day(2026, 12, 15))
        #expect(try addDue(on: day(2027, 6, 1)) == 2)
        #expect(gym.hasEnded(calendar: utc))
        #expect(try RecurringScheduler.nextDueDate(in: context, calendar: utc) == nil)
    }

    @Test func stopsAfterACountedNumberOfTimes() throws {
        let installments = rule(remainingCount: 3)
        #expect(try addDue(on: day(2027, 6, 1)) == 3)
        #expect(installments.remainingCount == 0)
        #expect(installments.hasEnded(calendar: utc))
    }

    // MARK: Kinds

    @Test func depositsAddMoney() throws {
        _ = rule(.deposit, amount: 2100, payee: "Employer", frequency: .twiceMonthly)
        #expect(try addDue(on: day(2026, 11, 30)) == 2)
        #expect(checking.balance == 7200)
    }

    @Test func transfersAreAddedAsLinkedPairs() throws {
        let saving = rule(.transfer, amount: 200, frequency: .weekly, interval: 2, start: day(2026, 11, 6), to: savings)
        #expect(try addDue(on: day(2026, 11, 30)) == 2, "Nov 6 and Nov 20")

        #expect(checking.balance == 2600)
        #expect(savings.balance == 900)
        let all = try transactions
        #expect(all.count == 4)
        #expect(all.allSatisfy { $0.kind == .transfer && $0.recurrence === saving && $0.transferCounterpart != nil })
    }

    @Test func checksTakeTheNextCheckNumbers() throws {
        Ledger.addTransaction(.check, amount: 50, to: checking, date: day(2026, 10, 5), payee: "Plumber", checkNumber: 1041, in: context)
        _ = rule(.check, amount: 1450, payee: "Landlord")

        #expect(try addDue(on: day(2026, 12, 2)) == 2)
        let checks = try transactions.filter { $0.payee == "Landlord" }.compactMap(\.checkNumber)
        #expect(checks == [1042, 1043])
    }

    @Test func aRuleThatNeedsAttentionIsLeftAlone() throws {
        let saving = rule(.transfer, to: savings)
        try context.save()
        context.delete(savings)
        try context.save()

        #expect(try addDue(on: day(2027, 1, 15)) == 0)
        #expect(saving.nextDate == day(2026, 11, 1), "it picks up from here once fixed")
        #expect(try transactions.isEmpty)
    }

    @Test func catchingUpStopsAtTheLimitAndContinuesNextTime() throws {
        let weekly = rule(frequency: .weekly, start: day(2010, 1, 4))
        #expect(try addDue(on: day(2026, 11, 20)) == RecurringScheduler.catchUpLimit)
        #expect(weekly.nextDate < day(2026, 11, 20))
        #expect(try addDue(on: day(2026, 11, 20)) == RecurringScheduler.catchUpLimit)
    }

    // MARK: Skip and add now

    @Test func skipNextMovesOnWithoutAdding() throws {
        let gym = rule(remainingCount: 5)
        RecurringScheduler.skipNext(gym, calendar: utc)
        #expect(gym.nextDate == day(2026, 12, 1))
        #expect(gym.remainingCount == 4, "a skipped occurrence counts toward the end")
        #expect(try addDue(on: day(2026, 11, 20)) == 0)
    }

    @Test func addNowAddsTheNextOccurrenceToday() throws {
        let gym = rule(start: day(2026, 12, 1))
        let added = try #require(RecurringScheduler.addNow(gym, in: context, now: day(2026, 11, 25).addingTimeInterval(3600), calendar: utc))
        #expect(added.date == day(2026, 11, 25))
        #expect(gym.nextDate == day(2027, 1, 1), "December's was added early")
        #expect(try addDue(on: day(2026, 12, 15)) == 0)
    }

    @Test func addNowDoesNothingForAnEndedRule() {
        let finished = rule(remainingCount: 0)
        #expect(RecurringScheduler.addNow(finished, in: context, now: day(2026, 11, 25), calendar: utc) == nil)
    }

    // MARK: Next due date

    @Test func nextDueDateIsTheEarliestActiveRule() throws {
        _ = rule(start: day(2026, 12, 15))
        _ = rule(start: day(2026, 12, 3))
        _ = rule(start: day(2026, 12, 1), remainingCount: 0)
        #expect(try RecurringScheduler.nextDueDate(in: context, calendar: utc) == day(2026, 12, 3))
    }
}
