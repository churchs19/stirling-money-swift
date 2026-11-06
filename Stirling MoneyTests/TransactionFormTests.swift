import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

@MainActor
struct TransactionFormTests {
    private func makeAccounts(in context: ModelContext) -> (checking: Account, savings: Account) {
        let checking = Account(name: "Checking", initialBalance: 100)
        let savings = Account(name: "Savings")
        context.insert(checking)
        context.insert(savings)
        return (checking, savings)
    }

    // MARK: Validation

    @Test func validationRequiresAmountAndPayeeOrOtherAccount() throws {
        let container = try makeInMemoryContainer()
        let (checking, savings) = makeAccounts(in: container.mainContext)

        var draft = TransactionDraft(account: checking)
        #expect(!draft.isValid)

        draft.payee = "  Grocer "
        #expect(!draft.isValid, "an amount is required")
        draft.amountText = "0"
        #expect(!draft.isValid, "zero isn't an amount")
        #expect(draft.hasInvalidAmount)
        draft.amountText = "abc"
        #expect(draft.hasInvalidAmount)
        draft.amountText = Decimal(string: "1234.50")!.formatted(.localCurrency)
        #expect(draft.amount == Decimal(string: "1234.50"), "currency text parses back")
        draft.amountText = "-12.50"
        #expect(draft.isValid)
        #expect(draft.amount == Decimal(string: "12.50"), "the kind decides the sign")

        draft.payee = "   "
        #expect(!draft.isValid, "a payee is required")

        draft.kind = .transfer
        #expect(!draft.isValid, "a transfer needs the other account, not a payee")
        draft.otherAccount = savings
        #expect(draft.isValid)
    }

    @Test func checkNumberIsOptionalButMustBeAWholeNumber() throws {
        let container = try makeInMemoryContainer()
        let (checking, _) = makeAccounts(in: container.mainContext)

        var draft = TransactionDraft(account: checking)
        draft.kind = .check
        draft.amountText = "40"
        draft.payee = "Landlord"
        #expect(draft.checkNumberText == "1", "defaults to the next check number")
        #expect(draft.isValid)

        draft.checkNumberText = ""
        #expect(draft.isValid)
        draft.checkNumberText = "12a"
        #expect(!draft.isValid)
        draft.checkNumberText = "0"
        #expect(!draft.isValid)

        // A bad check number doesn't matter once the kind isn't a check.
        draft.kind = .withdrawal
        #expect(draft.isValid)
    }

    @Test func editingDraftIsFilledFromTheTransaction() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let (checking, savings) = makeAccounts(in: context)
        let check = Ledger.addTransaction(.check, amount: 1450, to: checking, payee: "Landlord", checkNumber: 1001, in: context)
        let (_, incoming) = Ledger.addTransfer(amount: 25, from: checking, to: savings, in: context)

        let checkDraft = TransactionDraft(editing: check)
        #expect(checkDraft.kind == .check)
        #expect(checkDraft.amountText == Decimal(1450).formatted(.localCurrency), "shown as currency")
        #expect(checkDraft.amount == 1450)
        #expect(checkDraft.checkNumberText == "1001")
        #expect(checkDraft.payee == "Landlord")

        let transferDraft = TransactionDraft(editing: incoming)
        #expect(transferDraft.kind == .transfer)
        #expect(transferDraft.otherAccount === checking)
        #expect(transferDraft.isIncomingTransfer)
    }

    // MARK: Saving new entries

    @Test func savingNewEntriesAppliesSignAndCategory() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let (checking, savings) = makeAccounts(in: context)

        var draft = TransactionDraft(account: checking)
        draft.amountText = "30"
        draft.payee = " Grocer "
        draft.category = try Ledger.category(named: "Groceries", in: context)
        let withdrawal = try #require(Ledger.save(draft, in: checking, context: context))
        #expect(withdrawal.amount == -30)
        #expect(withdrawal.payee == "Grocer")
        #expect(withdrawal.category?.name == "Groceries")

        var transfer = TransactionDraft(account: checking)
        transfer.kind = .transfer
        transfer.amountText = "50"
        transfer.payee = "ignored"
        transfer.otherAccount = savings
        let outgoing = try #require(Ledger.save(transfer, in: checking, context: context))
        #expect(outgoing.amount == -50)
        #expect(outgoing.transferCounterpart?.account === savings)
        #expect(checking.balance == 20)
        #expect(savings.balance == 50)
    }

    @Test func invalidDraftSavesNothing() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let (checking, _) = makeAccounts(in: context)

        var draft = TransactionDraft(account: checking)
        draft.amountText = "30"
        #expect(Ledger.save(draft, in: checking, context: context) == nil)

        // A transfer to the same account would cancel itself out.
        draft.kind = .transfer
        draft.otherAccount = checking
        #expect(Ledger.save(draft, in: checking, context: context) == nil)
        #expect(try context.fetchCount(FetchDescriptor<AccountTransaction>()) == 0)
    }

    // MARK: Editing

    @Test func editingChangesKindSignAndDropsCheckNumber() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let (checking, _) = makeAccounts(in: context)
        let check = Ledger.addTransaction(.check, amount: 40, to: checking, payee: "Landlord", checkNumber: 7, in: context)

        var draft = TransactionDraft(editing: check)
        draft.kind = .deposit
        draft.amountText = "45"
        let saved = Ledger.save(draft, in: checking, editing: check, context: context)

        #expect(saved === check)
        #expect(check.kind == .deposit)
        #expect(check.amount == 45)
        #expect(check.checkNumber == nil)
        #expect(checking.balance == 145)
    }

    @Test func editingTransferUpdatesBothHalves() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let (checking, savings) = makeAccounts(in: context)
        let brokerage = Account(name: "Brokerage")
        context.insert(brokerage)
        let (outgoing, incoming) = Ledger.addTransfer(amount: 40, from: checking, to: savings, isPosted: true, in: context)

        var draft = TransactionDraft(editing: incoming)
        draft.amountText = "60"
        draft.date = day(2026, 3, 15)
        draft.note = "Moved"
        draft.otherAccount = brokerage
        draft.isPosted = false
        Ledger.save(draft, in: savings, editing: incoming, context: context)

        #expect(incoming.amount == 60)
        #expect(outgoing.amount == -60)
        #expect(outgoing.account === brokerage)
        #expect(outgoing.date == day(2026, 3, 15))
        #expect(outgoing.note == "Moved")
        #expect(!incoming.isPosted)
        #expect(outgoing.isPosted, "each side clears separately")
        #expect(checking.balance == 100)
        #expect(brokerage.balance == -60)
        #expect(savings.balance == 60)
    }

    @Test func changingTransferToWithdrawalRemovesOtherHalf() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let (checking, savings) = makeAccounts(in: context)
        let (outgoing, _) = Ledger.addTransfer(amount: 40, from: checking, to: savings, in: context)
        try context.save()

        var draft = TransactionDraft(editing: outgoing)
        draft.kind = .withdrawal
        draft.payee = "ATM"
        let saved = try #require(Ledger.save(draft, in: checking, editing: outgoing, context: context))
        try context.save()

        #expect(saved.kind == .withdrawal)
        #expect(saved.amount == -40)
        #expect(saved.transferCounterpart == nil)
        #expect(try context.fetchCount(FetchDescriptor<AccountTransaction>()) == 1)
        #expect(checking.balance == 60)
        #expect(savings.balance == 0)
    }

    @Test func changingWithdrawalToTransferCreatesPair() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let (checking, savings) = makeAccounts(in: context)
        let withdrawal = Ledger.addTransaction(.withdrawal, amount: 40, to: checking, payee: "ATM", in: context)
        try context.save()

        var draft = TransactionDraft(editing: withdrawal)
        draft.kind = .transfer
        draft.otherAccount = savings
        let saved = try #require(Ledger.save(draft, in: checking, editing: withdrawal, context: context))
        try context.save()

        #expect(saved.kind == .transfer)
        #expect(saved.displayPayee == "Transfer to Savings")
        #expect(try context.fetchCount(FetchDescriptor<AccountTransaction>()) == 2)
        #expect(checking.balance == 60)
        #expect(savings.balance == 40)
    }

    @Test func editingTransferWhoseOtherAccountWasDeletedRelinksIt() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let (checking, savings) = makeAccounts(in: context)
        let (outgoing, _) = Ledger.addTransfer(amount: 40, from: checking, to: savings, in: context)
        try context.save()
        context.delete(savings)
        try context.save()
        #expect(outgoing.transferCounterpart == nil)

        let brokerage = Account(name: "Brokerage")
        context.insert(brokerage)
        var draft = TransactionDraft(editing: outgoing)
        #expect(draft.otherAccount == nil)
        draft.otherAccount = brokerage
        Ledger.save(draft, in: checking, editing: outgoing, context: context)

        #expect(outgoing.displayPayee == "Transfer to Brokerage")
        #expect(outgoing.transferCounterpart?.transferCounterpart === outgoing)
        #expect(brokerage.balance == 40)
    }

    // MARK: Categories

    @Test func existingCategoryLookupCanExcludeTheOneBeingRenamed() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let groceries = try #require(try Ledger.category(named: "Groceries", in: context))
        _ = try Ledger.category(named: "Dining", in: context)

        #expect(try Ledger.existingCategory(named: "groceries", in: context) === groceries)
        #expect(try Ledger.existingCategory(named: "GROCERIES", excluding: groceries, in: context) == nil)
        #expect(try Ledger.existingCategory(named: "dining", excluding: groceries, in: context) != nil)
    }

    @Test func deletingCategoryKeepsTransactionsAndDeletesBudgets() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let (checking, _) = makeAccounts(in: context)
        let groceries = try #require(try Ledger.category(named: "Groceries", in: context))
        let transaction = Ledger.addTransaction(.withdrawal, amount: 5, to: checking, payee: "Grocer", category: groceries, in: context)
        let budget = Budget(name: "Food", amount: 400, period: .monthly, startDate: day(2026, 1, 1))
        context.insert(budget)
        budget.category = groceries
        try context.save()

        context.delete(groceries)
        try context.save()

        #expect(transaction.category == nil)
        #expect(try context.fetchCount(FetchDescriptor<AccountTransaction>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Budget>()) == 0)
    }
}
