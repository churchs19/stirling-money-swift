import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

/// Models to CloudKit records and back, with no network: what one device uploads, another applies.
@MainActor
struct CloudRecordTests {
    /// A book with one of everything: categories, accounts, a categorized transaction, a transfer, a budget, a goal,
    /// and a recurring transfer that has added an occurrence.
    private func fullBook(in context: ModelContext) throws -> Book {
        let book = Book(name: "Household", createdAt: day(2026, 3, 4))
        context.insert(book)
        let checking = Account(name: "Checking", initialBalance: Decimal(string: "1234567.89")!, iconName: "house")
        let savings = Account(name: "Savings", initialBalance: 0)
        for account in [checking, savings] {
            context.insert(account)
            account.book = book
        }
        let food = try #require(try Ledger.category(named: "Food", book: book, in: context))
        Ledger.addTransaction(
            .check, amount: Decimal(string: "0.1")!, to: checking, date: day(2026, 11, 2), payee: "Grocer",
            note: "Weekly", isPosted: true, checkNumber: 1042, category: food, in: context
        )
        Ledger.addTransfer(amount: 250, from: checking, to: savings, date: day(2026, 11, 3), in: context)

        var budget = BudgetDraft()
        budget.name = "Food"
        budget.amountText = "400"
        budget.category = food
        budget.period = .weekly
        _ = try #require(budget.save(book: book, in: context))

        var goal = GoalDraft(account: savings)
        goal.name = "Roof"
        goal.targetText = "5000"
        _ = try #require(goal.save(in: context))

        var rule = RecurringDraft(account: checking, now: day(2026, 11, 1), calendar: utc)
        rule.kind = .transfer
        rule.otherAccount = savings
        rule.amountText = "100"
        rule.end = .afterCount
        rule.countText = "12"
        _ = try #require(rule.save(in: context, now: day(2026, 11, 1), calendar: utc))
        try RecurringScheduler.addDue(in: context, now: day(2026, 11, 1), calendar: utc)
        try context.save()
        return book
    }

    /// A book with the same `syncID` in another store, as on a second device.
    private func emptyCopy(of book: Book, in context: ModelContext) -> Book {
        let copy = Book(name: "")
        copy.syncID = book.syncID
        context.insert(copy)
        return copy
    }

    @Test func aWholeBookSurvivesTheRoundTrip() throws {
        let source = try makeInMemoryContainer()
        let book = try fullBook(in: source.mainContext)
        let records = book.allRecords()

        let target = try makeInMemoryContainer()
        let context = target.mainContext
        let copy = emptyCopy(of: book, in: context)
        // In reverse, so transactions come before their accounts and categories.
        let unresolved = try RecordImporter.apply(records.reversed(), to: copy, in: context)
        #expect(unresolved.isEmpty)
        try context.save()

        #expect(copy.name == "Household")
        #expect(copy.createdAt == day(2026, 3, 4))

        let accounts = try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)]))
        #expect(accounts.map(\.name) == ["Checking", "Savings"])
        #expect(accounts.allSatisfy { $0.book === copy })
        let checking = accounts[0], savings = accounts[1]
        #expect(checking.initialBalance == Decimal(string: "1234567.89"))
        #expect(checking.iconName == "house")

        // Balances come out the same, since they're computed from the same transactions.
        let original = try #require(book.accounts?.first { $0.name == "Checking" })
        #expect(checking.balance == original.balance)
        #expect(savings.balance == 350)

        let check = try #require(checking.transactions?.first { $0.kind == .check })
        #expect(check.amount == Decimal(string: "-0.1"))
        #expect(check.payee == "Grocer" && check.note == "Weekly" && check.isPosted)
        #expect(check.checkNumber == 1042)
        #expect(check.date == day(2026, 11, 2))
        #expect(check.category?.name == "Food")

        // Both transfers (the one entered and the recurring one) are linked pairs again.
        let transfersOut = (checking.transactions ?? []).filter { $0.kind == .transfer }
        #expect(transfersOut.count == 2)
        #expect(transfersOut.allSatisfy { $0.transferCounterpart?.account === savings })

        let budget = try #require(copy.budgets?.first)
        #expect(budget.amount == 400 && budget.period == .weekly && budget.category?.name == "Food")
        let goal = try #require(copy.goals?.first)
        #expect(goal.account === savings && goal.targetAmount == 5000)

        let rule = try #require(copy.recurringTransactions?.first)
        #expect(rule.kind == .transfer && rule.account === checking && rule.otherAccount === savings)
        #expect(rule.remainingCount == 11)
        #expect(rule.nextDate == day(2026, 12, 1))
        #expect(rule.transactions?.count == 2, "both halves of the occurrence it added")
    }

    @Test func referencesToRecordsInALaterBatchAreRetried() throws {
        let source = try makeInMemoryContainer()
        let book = try fullBook(in: source.mainContext)
        let records = book.allRecords()
        let transactions = records.filter { $0.recordType == AccountTransaction.recordType }
        let others = records.filter { $0.recordType != AccountTransaction.recordType }

        let target = try makeInMemoryContainer()
        let context = target.mainContext
        let copy = emptyCopy(of: book, in: context)
        // Transactions only: their accounts haven't arrived.
        let pending = try RecordImporter.apply(transactions, to: copy, in: context)
        #expect(pending.count == transactions.count)

        let stillPending = try RecordImporter.apply(others, to: copy, in: context, retrying: pending)
        #expect(stillPending.isEmpty)
        let checking = try #require(copy.accounts?.first { $0.name == "Checking" })
        #expect(checking.transactions?.count == 3)
    }

    @Test func applyingAgainUpdatesInsteadOfAdding() throws {
        let source = try makeInMemoryContainer()
        let sourceContext = source.mainContext
        let book = try fullBook(in: sourceContext)

        let target = try makeInMemoryContainer()
        let context = target.mainContext
        let copy = emptyCopy(of: book, in: context)
        try RecordImporter.apply(book.allRecords(), to: copy, in: context)

        // Renamed, and the check's category removed, on the first device.
        let checking = try #require(book.accounts?.first { $0.name == "Checking" })
        checking.name = "Everyday"
        let check = try #require(checking.transactions?.first { $0.kind == .check })
        check.category = nil
        try RecordImporter.apply(book.allRecords(), to: copy, in: context)

        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<AccountTransaction>()) == 5)
        let copiedCheck = try #require(try context.fetch(FetchDescriptor<AccountTransaction>()).first { $0.syncID == check.syncID })
        #expect(copiedCheck.account?.name == "Everyday")
        #expect(copiedCheck.category == nil)
    }

    @Test func recordsOnlyMatchModelsInTheSameBook() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let personal = Book(name: "Personal")
        let household = Book(name: "Household")
        context.insert(personal)
        context.insert(household)
        let account = Account(name: "Checking")
        context.insert(account)
        account.book = personal

        // The same name in another book's zone is a different record.
        let record = account.makeRecord(in: household.zoneID)
        try RecordImporter.apply([record], to: household, in: context)
        #expect(account.book === personal)
        #expect(household.accounts?.count == 1)
    }

    // MARK: Values

    @Test func valuesAreEncryptedAndMoneyIsExact() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let book = Book(name: "Personal")
        context.insert(book)
        let account = try Account(name: "Checking", initialBalance: #require(Decimal(string: "-0.07")))
        context.insert(account)
        account.book = book

        let record = account.makeRecord(in: book.zoneID)
        #expect(record.recordType == "Account")
        #expect(record.recordID.recordName == account.syncID)
        #expect(record.recordID.zoneID.zoneName == "Book-\(book.syncID)")
        #expect(record["name"] == nil, "values go in encryptedValues")
        #expect(record.string("name") == "Checking")
        #expect(record.string("initialBalance") == "-0.07")

        // Whatever the locale, a decimal comma never sneaks in.
        let german = Decimal(string: "1234,5", locale: Locale(identifier: "de_DE"))
        record.setValue(german, for: "initialBalance")
        #expect(record.string("initialBalance") == "1234.5")
        #expect(record.decimal("initialBalance") == Decimal(string: "1234.5"))
    }

    @Test func savedSystemFieldsKeepTheRecordsIdentity() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let book = Book(name: "Personal")
        context.insert(book)
        let category = Category(name: "Food")
        context.insert(category)
        category.book = book

        let first = category.makeRecord(in: book.zoneID)
        category.remember(first)
        #expect(category.ckSystemFields != nil)

        category.name = "Groceries"
        let second = category.makeRecord(in: book.zoneID)
        #expect(second.recordID == first.recordID)
        #expect(second.recordType == first.recordType)
        #expect(second.string("name") == "Groceries")
    }

    @Test func unknownRecordTypesAreSkipped() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let book = Book(name: "Personal")
        context.insert(book)
        let future = CKRecord(recordType: "Attachment", recordID: CKRecord.ID(recordName: "x", zoneID: book.zoneID))
        #expect(try RecordImporter.apply([future], to: book, in: context).isEmpty)
    }

    // MARK: Zones and names

    @Test func zonesAreNamedForTheirBook() {
        let book = Book(name: "Personal")
        #expect(book.zoneID.ownerName == CKCurrentUserDefaultName)
        #expect(Book.syncID(ofZone: book.zoneID) == book.syncID)
        #expect(Book.syncID(ofZone: CKRecordZone.ID(zoneName: "Other")) == nil)

        book.zoneOwnerName = "_owner"
        #expect(book.zoneID.ownerName == "_owner")
    }

    @Test func transferHalvesNameEachOther() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking")
        let savings = Account(name: "Savings")
        context.insert(checking)
        context.insert(savings)
        let pair = Ledger.addTransfer(amount: 10, from: checking, to: savings, pairID: "p", in: context)
        #expect(pair.outgoing.syncID == "p:out")
        #expect(pair.incoming.syncID == "p:in")
        #expect(Ledger.counterpartSyncID(of: "p:out", isIncoming: false) == "p:in")
        #expect(Ledger.counterpartSyncID(of: "p:in", isIncoming: true) == "p:out")
        #expect(Ledger.counterpartSyncID(of: "old", isIncoming: false) == "old:in")
    }

    @Test func twoDevicesAddingTheSameOccurrenceNameItTheSame() throws {
        // The same rule (same syncID) on two devices, each adding what's due.
        var names: [[String]] = []
        for _ in 0 ..< 2 {
            let container = try makeInMemoryContainer()
            let context = container.mainContext
            let checking = Account(name: "Checking")
            context.insert(checking)
            var draft = RecurringDraft(account: checking, now: day(2026, 11, 1), calendar: utc)
            draft.payee = "Rent"
            draft.amountText = "900"
            let rule = try #require(draft.save(in: context, now: day(2026, 11, 1), calendar: utc))
            rule.syncID = "rent"
            try RecurringScheduler.addDue(in: context, now: day(2027, 1, 15), calendar: utc)
            names.append((rule.transactions ?? []).map(\.syncID).sorted())
        }
        #expect(names[0] == ["rent:2026-11-01", "rent:2026-12-01", "rent:2027-01-01"])
        #expect(names[0] == names[1])
    }

    @Test func addingAnOccurrenceEarlyUsesItsDueDatesName() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let checking = Account(name: "Checking")
        context.insert(checking)
        var draft = RecurringDraft(account: checking, now: day(2026, 11, 1), calendar: utc)
        draft.payee = "Rent"
        draft.amountText = "900"
        draft.startDate = day(2026, 12, 1)
        let rule = try #require(draft.save(in: context, now: day(2026, 11, 1), calendar: utc))

        let early = try #require(RecurringScheduler.addNow(rule, in: context, now: day(2026, 11, 20), calendar: utc))
        #expect(early.date == day(2026, 11, 20))
        #expect(early.syncID == "\(rule.syncID):2026-12-01")
    }
}
