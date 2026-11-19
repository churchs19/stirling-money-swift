import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

/// The recurring transaction model and what happens to it when related things are deleted.
@MainActor
struct RecurringTransactionTests {
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

    /// A monthly rent payment from Checking, inserted before its relationships are set.
    private func rent(category: Stirling_Money.Category? = nil) -> RecurringTransaction {
        let rule = RecurringTransaction(
            kind: .check, amount: 1450, payee: "Landlord", frequency: .monthly, startDate: day(2026, 12, 1), calendar: utc
        )
        context.insert(rule)
        rule.account = checking
        rule.category = category
        return rule
    }

    /// A transfer of $200 from Checking to Savings every other Friday.
    private func savingsTransfer() -> RecurringTransaction {
        let rule = RecurringTransaction(
            kind: .transfer, amount: 200, frequency: .weekly, interval: 2, startDate: day(2026, 11, 20), calendar: utc
        )
        context.insert(rule)
        rule.account = checking
        rule.otherAccount = savings
        return rule
    }

    // MARK: The model

    @Test func newRuleStartsOnItsStartDayWithAPositiveAmount() {
        let rule = RecurringTransaction(
            kind: .withdrawal, amount: -12.99, payee: "Streaming", frequency: .monthly,
            startDate: day(2026, 11, 22).addingTimeInterval(9 * 3600), calendar: utc
        )
        #expect(rule.amount == 12.99, "the kind decides the sign")
        #expect(rule.startDate == day(2026, 11, 22))
        #expect(rule.nextDate == day(2026, 11, 22))
        #expect(rule.kind == .withdrawal)
        #expect(rule.frequency == .monthly)
        #expect(rule.schedule == RecurrenceSchedule(frequency: .monthly, interval: 1, start: day(2026, 11, 22), secondDay: 15))
    }

    @Test func unknownStoredValuesFallBackSafely() {
        let rule = rent()
        rule.kindRawValue = "nonsense"
        rule.frequencyRawValue = "hourly"
        #expect(rule.kind == .withdrawal)
        #expect(rule.frequency == .monthly)
    }

    @Test func endsWhenTheCountIsUsedUpOrTheNextDateIsPastTheEnd() {
        let rule = rent()
        #expect(!rule.hasEnded(calendar: utc))

        rule.remainingCount = 2
        #expect(!rule.hasEnded(calendar: utc))
        rule.remainingCount = 0
        #expect(rule.hasEnded(calendar: utc))

        rule.remainingCount = nil
        rule.endDate = day(2027, 3, 1)
        rule.nextDate = day(2027, 3, 1)
        #expect(!rule.hasEnded(calendar: utc), "the end date itself still counts")
        rule.nextDate = day(2027, 4, 1)
        #expect(rule.hasEnded(calendar: utc))
    }

    @Test func transfersNameTheOtherAccount() {
        let transfer = savingsTransfer()
        #expect(transfer.displayPayee == "Transfer to Savings")
        #expect(transfer.problem == nil)
        #expect(rent().displayPayee == "Landlord")
    }

    // MARK: Deleting related things

    @Test func deletingTheAccountDeletesItsRules() throws {
        _ = rent()
        _ = savingsTransfer()
        try context.save()

        context.delete(checking)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<RecurringTransaction>()).isEmpty)
    }

    @Test func deletingATransfersOtherAccountLeavesTheRuleNeedingAttention() throws {
        let transfer = savingsTransfer()
        try context.save()

        context.delete(savings)
        try context.save()

        let rules = try context.fetch(FetchDescriptor<RecurringTransaction>())
        #expect(rules.count == 1)
        #expect(transfer.otherAccount == nil)
        #expect(transfer.account === checking)
        #expect(transfer.problem != nil)
    }

    @Test func deletingTheCategoryKeepsTheRuleUncategorized() throws {
        let housing = try #require(try Ledger.category(named: "Housing", in: context))
        let rule = rent(category: housing)
        try context.save()

        context.delete(housing)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<RecurringTransaction>()).count == 1)
        #expect(rule.category == nil)
    }

    @Test func deletingTheRuleKeepsTheTransactionsItAdded() throws {
        let rule = rent()
        let added = Ledger.addTransaction(.check, amount: 1450, to: checking, date: day(2026, 12, 1), payee: "Landlord", in: context)
        added.recurrence = rule
        try context.save()
        #expect(rule.transactions?.count == 1)

        context.delete(rule)
        try context.save()

        let transactions = try context.fetch(FetchDescriptor<AccountTransaction>())
        #expect(transactions.count == 1)
        #expect(transactions.first?.recurrence == nil)
        #expect(checking.balance == -1450)
    }

    @Test func deletingAnAddedTransactionKeepsTheRule() throws {
        let rule = rent()
        let added = Ledger.addTransaction(.check, amount: 1450, to: checking, date: day(2026, 12, 1), payee: "Landlord", in: context)
        added.recurrence = rule
        try context.save()

        Ledger.delete(added, in: context)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<RecurringTransaction>()).count == 1)
        #expect(rule.transactions?.isEmpty ?? true)
    }

    @Test func aRuleWhoseAccountIsGoneSaysSo() {
        let orphan = RecurringTransaction(kind: .withdrawal, amount: 5, frequency: .weekly, startDate: day(2026, 11, 20), calendar: utc)
        context.insert(orphan)
        #expect(orphan.problem != nil)
    }
}
