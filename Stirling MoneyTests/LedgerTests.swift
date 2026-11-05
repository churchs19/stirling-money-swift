import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

@MainActor
struct LedgerTests {
    @Test func balancesIncludeAllOrOnlyPostedTransactions() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking", initialBalance: 100)
        context.insert(checking)

        try Ledger.addTransaction(.withdrawal, amount: #require(Decimal(string: "25.50")), to: checking, payee: "Grocer", in: context)
        Ledger.addTransaction(.deposit, amount: 10, to: checking, payee: "Refund", isPosted: true, in: context)

        #expect(try checking.balance == #require(Decimal(string: "84.50")))
        #expect(checking.postedBalance == 110)
        #expect(checking.transactionCount == 2)
    }

    @Test func kindDecidesSignWhicheverWayAmountIsEntered() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let account = Account(name: "Checking")
        context.insert(account)

        let withdrawal = Ledger.addTransaction(.withdrawal, amount: -20, to: account, payee: "A", in: context)
        let deposit = Ledger.addTransaction(.deposit, amount: -30, to: account, payee: "B", in: context)
        let check = Ledger.addTransaction(.check, amount: 40, to: account, payee: "C", checkNumber: 7, in: context)

        #expect(withdrawal.amount == -20)
        #expect(deposit.amount == 30)
        #expect(check.amount == -40)
    }

    @Test func nextCheckNumberFollowsHighestCheck() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let account = Account(name: "Checking")
        context.insert(account)
        #expect(account.nextCheckNumber == 1)

        Ledger.addTransaction(.check, amount: 5, to: account, payee: "A", checkNumber: 1001, in: context)
        Ledger.addTransaction(.check, amount: 5, to: account, payee: "B", checkNumber: 998, in: context)
        // A check number on a non-check is dropped, so it can't affect numbering.
        Ledger.addTransaction(.withdrawal, amount: 5, to: account, payee: "C", checkNumber: 5000, in: context)

        #expect(account.nextCheckNumber == 1002)
    }

    @Test func transferCreatesLinkedPair() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking", initialBalance: 100)
        let savings = Account(name: "Savings")
        context.insert(checking)
        context.insert(savings)

        let (outgoing, incoming) = Ledger.addTransfer(amount: 40, from: checking, to: savings, in: context)

        #expect(checking.balance == 60)
        #expect(savings.balance == 40)
        #expect(outgoing.transferCounterpart === incoming)
        #expect(incoming.transferCounterpart === outgoing)
        #expect(outgoing.displayPayee == "Transfer to Savings")
        #expect(incoming.displayPayee == "Transfer from Checking")

        savings.name = "Rainy Day"
        #expect(outgoing.displayPayee == "Transfer to Rainy Day")
    }

    @Test func deletingEitherHalfOfTransferDeletesBoth() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking")
        let savings = Account(name: "Savings")
        context.insert(checking)
        context.insert(savings)
        let (_, incoming) = Ledger.addTransfer(amount: 40, from: checking, to: savings, in: context)
        try context.save()

        Ledger.delete(incoming, in: context)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<AccountTransaction>()) == 0)
        #expect(checking.balance == 0)
        #expect(savings.balance == 0)
    }

    @Test func deletingAccountDeletesItsTransactionsAndGoals() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let account = Account(name: "Checking")
        context.insert(account)
        Ledger.addTransaction(.withdrawal, amount: 5, to: account, payee: "A", in: context)
        let goal = Goal(name: "Trip", targetAmount: 500, targetDate: .now, initialBalance: 0)
        context.insert(goal)
        goal.account = account
        try context.save()

        context.delete(account)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<AccountTransaction>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Goal>()) == 0)
    }

    @Test func categoryLookupReusesExistingIgnoringCase() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let first = try Ledger.category(named: "Groceries", in: context)
        let second = try Ledger.category(named: "  groceries ", in: context)

        #expect(first != nil)
        #expect(first === second)
        #expect(try Ledger.category(named: "   ", in: context) == nil)
        #expect(try context.fetchCount(FetchDescriptor<Stirling_Money.Category>()) == 1)
    }
}
