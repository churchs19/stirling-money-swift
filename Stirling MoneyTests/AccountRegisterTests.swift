import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

@MainActor
struct AccountRegisterTests {
    @Test func deletingAccountKeepsOtherHalfOfTransfer() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking")
        let savings = Account(name: "Savings")
        context.insert(checking)
        context.insert(savings)
        let (_, incoming) = Ledger.addTransfer(amount: 40, from: checking, to: savings, in: context)
        try context.save()

        context.delete(checking)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<AccountTransaction>()) == 1)
        #expect(savings.balance == 40)
        #expect(incoming.transferCounterpart == nil)
        #expect(incoming.displayPayee == "Transfer from a deleted account")
    }

    @Test func sortByNameIgnoresCaseAndOrdersNumbersNaturally() {
        let accounts = ["savings", "Checking", "Account 10", "Account 2"].map { Account(name: $0) }
        #expect(AccountSort.name.sorted(accounts).map(\.name) == ["Account 2", "Account 10", "Checking", "savings"])
    }

    @Test func sortByMostUsedFallsBackToName() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let quiet = Account(name: "A Quiet")
        let busy = Account(name: "Z Busy")
        let alsoQuiet = Account(name: "B Quiet")
        [quiet, busy, alsoQuiet].forEach(context.insert)
        Ledger.addTransaction(.withdrawal, amount: 1, to: busy, payee: "One", in: context)
        Ledger.addTransaction(.withdrawal, amount: 1, to: busy, payee: "Two", in: context)

        #expect(AccountSort.mostUsed.sorted([quiet, alsoQuiet, busy]).map(\.name) == ["Z Busy", "A Quiet", "B Quiet"])
    }

    @Test func searchMatchesPayeeNoteCategoryAndCheckNumber() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let account = Account(name: "Checking")
        context.insert(account)
        let groceries = try Ledger.category(named: "Groceries", in: context)
        let transaction = Ledger.addTransaction(
            .check, amount: 50, to: account, payee: "Corner Grocer", note: "Birthday cake",
            checkNumber: 1042, category: groceries, in: context
        )

        #expect(transaction.matches(searchText: "corner"))
        #expect(transaction.matches(searchText: "CAKE"))
        #expect(transaction.matches(searchText: "grocer"))
        #expect(transaction.matches(searchText: "1042"))
        #expect(transaction.matches(searchText: "  "))
        #expect(!transaction.matches(searchText: "rent"))
    }

    @Test func searchFindsTransfersByOtherAccountName() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking")
        let savings = Account(name: "Savings")
        context.insert(checking)
        context.insert(savings)
        let (outgoing, _) = Ledger.addTransfer(amount: 10, from: checking, to: savings, in: context)

        #expect(outgoing.matches(searchText: "savings"))
    }

    @Test func userInputParsesNumbersAndTreatsBlankAsZero() {
        #expect(Decimal(userInput: "1250.75") == Decimal(string: "1250.75"))
        #expect(Decimal(userInput: "-342.18") == Decimal(string: "-342.18"))
        #expect(Decimal(userInput: "  ") == 0)
        #expect(Decimal(userInput: "abc") == nil)

        // Text shown with the currency format parses back, whatever the test machine's locale.
        let amount = Decimal(string: "-1250.75")!
        #expect(Decimal(userInput: amount.formatted(.localCurrency)) == amount)
        #expect(Decimal(string: "1250.75")?.editableText == "1250.75")
    }
}
