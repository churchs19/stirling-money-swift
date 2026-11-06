import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

@MainActor
struct TransactionCSVTests {
    @Test func exportsEveryTransactionOldestFirst() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking")
        let savings = Account(name: "Savings")
        context.insert(checking)
        context.insert(savings)
        let food = try Ledger.category(named: "Food", in: context)
        Ledger.addTransaction(.check, amount: 1234.5, to: checking, date: day(2026, 11, 2), payee: "Landlord", isPosted: true, checkNumber: 1001, in: context)
        Ledger.addTransaction(.withdrawal, amount: 12.25, to: checking, date: day(2026, 11, 1), payee: "Grocer, Inc.", note: "Said \"thanks\"", category: food, in: context)
        Ledger.addTransfer(amount: 50, from: checking, to: savings, date: day(2026, 11, 3), in: context)
        let all = try context.fetch(FetchDescriptor<AccountTransaction>())

        let lines = try TransactionCSV.make(all, timeZone: #require(TimeZone(identifier: "UTC"))).components(separatedBy: "\r\n")

        #expect(lines == [
            "Date,Account,Type,Payee,Category,Amount,Posted,Check Number,Note",
            "2026-11-01,Checking,Withdrawal,\"Grocer, Inc.\",Food,-12.25,No,,\"Said \"\"thanks\"\"\"",
            "2026-11-02,Checking,Check,Landlord,,-1234.5,Yes,1001,",
            "2026-11-03,Checking,Transfer,Transfer to Savings,,-50,No,,",
            "2026-11-03,Savings,Transfer,Transfer from Checking,,50,No,,",
            "",
        ])
    }

    @Test func escapesOnlyWhenNeeded() {
        #expect(TransactionCSV.escape("plain") == "plain")
        #expect(TransactionCSV.escape("a,b") == "\"a,b\"")
        #expect(TransactionCSV.escape("line\nbreak") == "\"line\nbreak\"")
        #expect(TransactionCSV.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }

    @Test func textThatLooksLikeAFormulaIsKeptAsText() {
        #expect(TransactionCSV.text("=SUM(A1)") == "'=SUM(A1)")
        #expect(TransactionCSV.text("@home") == "'@home")
        #expect(TransactionCSV.text("Coffee") == "Coffee")
        #expect(TransactionCSV.text("") == "")
    }
}
