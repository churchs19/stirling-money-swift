import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

/// The recurring transaction form (`RecurringDraft`), in a fixed UTC calendar.
@MainActor
struct RecurringDraftTests {
    private let container: ModelContainer
    private var context: ModelContext {
        container.mainContext
    }

    private let checking = Account(name: "Checking")
    private let savings = Account(name: "Savings")

    init() throws {
        container = try makeInMemoryContainer()
        container.mainContext.insert(checking)
        container.mainContext.insert(savings)
    }

    private func rentDraft() -> RecurringDraft {
        var draft = RecurringDraft(account: checking, now: day(2026, 11, 19), calendar: utc)
        draft.kind = .check
        draft.amountText = "1450"
        draft.payee = "Landlord"
        draft.startDate = day(2026, 12, 1)
        return draft
    }

    // MARK: A new form

    @Test func newFormStartsTodayMonthlyWithNoEnd() {
        let draft = RecurringDraft(account: checking, now: day(2026, 11, 19).addingTimeInterval(3600), calendar: utc)
        #expect(draft.startDate == day(2026, 11, 19))
        #expect(draft.frequency == .monthly)
        #expect(draft.end == .never)
        #expect(draft.account === checking)
        #expect(!draft.isValid(calendar: utc))
    }

    @Test func needsAnAmountAndAPayeeOrAnotherAccount() {
        var draft = rentDraft()
        #expect(draft.isValid(calendar: utc))
        draft.amountText = "0"
        #expect(!draft.isValid(calendar: utc))
        #expect(draft.hasInvalidAmount)
        draft.amountText = "1450"
        draft.payee = "  "
        #expect(!draft.isValid(calendar: utc))

        draft.kind = .transfer
        #expect(!draft.isValid(calendar: utc), "a transfer needs the other account")
        draft.otherAccount = checking
        #expect(!draft.isValid(calendar: utc), "not the same account")
        draft.otherAccount = savings
        #expect(draft.isValid(calendar: utc))
    }

    @Test func twiceAMonthNeedsTwoDifferentDays() {
        var draft = rentDraft()
        draft.frequency = .twiceMonthly
        draft.secondDay = 1
        #expect(draft.hasSameDayTwice(calendar: utc))
        #expect(!draft.isValid(calendar: utc))
        draft.secondDay = 15
        #expect(draft.isValid(calendar: utc))
    }

    @Test func endsMustBeAfterTheStartOrACountAboveZero() {
        var draft = rentDraft()
        draft.end = .onDate
        draft.endDate = day(2026, 11, 30)
        #expect(draft.endsBeforeStart(calendar: utc))
        #expect(!draft.isValid(calendar: utc))
        draft.endDate = day(2026, 12, 1)
        #expect(draft.isValid(calendar: utc), "ending on the start day is one occurrence")

        draft.end = .afterCount
        #expect(!draft.isValid(calendar: utc), "a count is needed")
        draft.countText = "0"
        #expect(draft.hasInvalidCount)
        draft.countText = "12"
        #expect(draft.isValid(calendar: utc))
    }

    @Test func previewListsTheNextFewOccurrencesWithinTheEnd() {
        var draft = rentDraft()
        #expect(draft.upcomingDates(now: day(2026, 11, 19), calendar: utc) == [day(2026, 12, 1), day(2027, 1, 1), day(2027, 2, 1)])
        draft.end = .afterCount
        draft.countText = "2"
        #expect(draft.upcomingDates(now: day(2026, 11, 19), calendar: utc).count == 2)
        draft.end = .onDate
        draft.endDate = day(2026, 12, 20)
        #expect(draft.upcomingDates(now: day(2026, 11, 19), calendar: utc) == [day(2026, 12, 1)])
    }

    // MARK: Filling the form

    @Test func makeRecurringStartsAMonthAfterTheTransaction() throws {
        let housing = try #require(try Ledger.category(named: "Housing", in: context))
        let check = Ledger.addTransaction(.check, amount: 1450, to: checking, date: day(2026, 11, 1), payee: "Landlord", checkNumber: 101, category: housing, in: context)

        let draft = RecurringDraft(from: check, calendar: utc)
        #expect(draft.kind == .check)
        #expect(Decimal(userInput: draft.amountText) == 1450)
        #expect(draft.payee == "Landlord")
        #expect(draft.category === housing)
        #expect(draft.account === checking)
        #expect(draft.startDate == day(2026, 12, 1))
    }

    @Test func makeRecurringFromEitherHalfOfATransferMovesMoneyTheSameWay() {
        let pair = Ledger.addTransfer(amount: 200, from: checking, to: savings, date: day(2026, 11, 5), in: context)
        for half in [pair.outgoing, pair.incoming] {
            let draft = RecurringDraft(from: half, calendar: utc)
            #expect(draft.kind == .transfer)
            #expect(draft.account === checking)
            #expect(draft.otherAccount === savings)
        }
    }

    @Test func editingFillsTheFormFromTheRule() throws {
        let rule = try #require(rentDraft().save(in: context, now: day(2026, 11, 19), calendar: utc))
        rule.remainingCount = 5
        let draft = RecurringDraft(editing: rule, calendar: utc)
        #expect(draft.payee == "Landlord")
        #expect(draft.startDate == day(2026, 12, 1))
        #expect(draft.end == .afterCount)
        #expect(draft.countText == "5")
    }

    // MARK: Saving

    @Test func savingCreatesARuleThatStartsOnItsStartDate() throws {
        var draft = rentDraft()
        draft.end = .afterCount
        draft.countText = "12"
        let rule = try #require(draft.save(in: context, now: day(2026, 11, 19), calendar: utc))
        #expect(rule.kind == .check)
        #expect(rule.amount == 1450)
        #expect(rule.account === checking)
        #expect(rule.nextDate == day(2026, 12, 1))
        #expect(rule.remainingCount == 12)
        #expect(rule.endDate == nil)
        #expect(try context.fetch(FetchDescriptor<RecurringTransaction>()).count == 1)
    }

    @Test func savingATransferDropsThePayeeAndCategory() throws {
        var draft = rentDraft()
        draft.kind = .transfer
        draft.otherAccount = savings
        draft.category = try Ledger.category(named: "Housing", in: context)
        let rule = try #require(draft.save(in: context, calendar: utc))
        #expect(rule.payee.isEmpty)
        #expect(rule.category == nil)
        #expect(rule.otherAccount === savings)
    }

    @Test func anInvalidFormSavesNothing() throws {
        var draft = rentDraft()
        draft.amountText = ""
        #expect(draft.save(in: context, calendar: utc) == nil)
        #expect(try context.fetch(FetchDescriptor<RecurringTransaction>()).isEmpty)
    }

    @Test func editingTheAmountLeavesTheNextDateAlone() throws {
        let rule = try #require(rentDraft().save(in: context, now: day(2026, 11, 19), calendar: utc))
        try RecurringScheduler.addDue(in: context, now: day(2027, 1, 10), calendar: utc)
        #expect(rule.nextDate == day(2027, 2, 1))

        var draft = RecurringDraft(editing: rule, calendar: utc)
        draft.amountText = "1500"
        draft.save(in: context, editing: rule, now: day(2027, 1, 10), calendar: utc)
        #expect(rule.amount == 1500)
        #expect(rule.nextDate == day(2027, 2, 1))
    }

    @Test func changingTheScheduleDoesNotAddPastOccurrencesAgain() throws {
        let rule = try #require(rentDraft().save(in: context, now: day(2026, 11, 19), calendar: utc))
        try RecurringScheduler.addDue(in: context, now: day(2027, 1, 10), calendar: utc)

        // Move rent to the 15th, starting back in December.
        var draft = RecurringDraft(editing: rule, calendar: utc)
        draft.startDate = day(2026, 12, 15)
        draft.save(in: context, editing: rule, now: day(2027, 1, 10), calendar: utc)

        #expect(rule.nextDate == day(2027, 1, 15), "from today, not from the new start")
        #expect(try RecurringScheduler.addDue(in: context, now: day(2027, 1, 10), calendar: utc) == 0)
    }

    @Test func perAccountAmountsAndPayeesForTransfers() throws {
        var draft = rentDraft()
        draft.kind = .transfer
        draft.amountText = "400"
        draft.otherAccount = savings
        let rule = try #require(draft.save(in: context, calendar: utc))
        #expect(rule.signedAmount(in: checking) == -400)
        #expect(rule.signedAmount(in: savings) == 400)
        #expect(rule.displayPayee(in: checking) == "Transfer to Savings")
        #expect(rule.displayPayee(in: savings) == "Transfer from Checking")
    }
}
