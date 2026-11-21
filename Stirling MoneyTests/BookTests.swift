import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

/// The store as it was before books: only what the upgrade test needs, under the same entity name.
enum StoreBeforeBooks {
    @Model
    final class Account {
        var name: String = ""
        var initialBalance: Decimal = 0
        var createdAt: Date = Date.now
        var iconName: String?

        init(name: String, initialBalance: Decimal) {
            self.name = name
            self.initialBalance = initialBalance
        }
    }
}

@MainActor
struct BookTests {
    // MARK: Preparing

    @Test func aNewStoreGetsOneBook() throws {
        let container = try makeInMemoryContainer()
        let book = try Books.prepare(in: container.mainContext)
        #expect(book.name == "My Book")
        #expect(book.canEdit && book.isOwnedByMe && !book.isShared)

        // Launching again doesn't make another.
        try Books.prepare(in: container.mainContext)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Book>()) == 1)
    }

    @Test func dataWithoutABookGoesIntoTheOldestBookWithNewSyncIDs() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let older = Book(name: "Personal", createdAt: day(2026, 1, 1))
        let newer = Book(name: "Household", createdAt: day(2026, 6, 1))
        context.insert(older)
        context.insert(newer)

        // As the store's migration leaves it: no book, and every row with the same syncID.
        let checking = Account(name: "Checking")
        let savings = Account(name: "Savings")
        context.insert(checking)
        context.insert(savings)
        let food = try #require(try Ledger.category(named: "Food", in: context))
        let payment = Ledger.addTransaction(.withdrawal, amount: 5, to: checking, payee: "Cafe", category: food, in: context)
        let transfer = Ledger.addTransfer(amount: 10, from: checking, to: savings, in: context)
        var budgetDraft = BudgetDraft()
        budgetDraft.name = "Food"
        budgetDraft.amountText = "100"
        let budget = try #require(budgetDraft.save(in: context))
        for model in [checking, savings, food, payment, transfer.outgoing, transfer.incoming, budget] as [any BookOwned] {
            model.syncID = "same"
        }

        #expect(try Books.prepare(in: context) === older)

        let models: [any BookOwned] = [checking, savings, food, payment, transfer.outgoing, transfer.incoming, budget]
        #expect(models.allSatisfy { $0.book === older })
        #expect(Set(models.map(\.syncID)).count == models.count, "every record gets its own syncID")
        #expect(!models.contains { $0.syncID == "same" })
    }

    @Test func upgradingAStoreFromBeforeBooks() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Upgrade.store")

        do {
            let old = try ModelContainer(for: StoreBeforeBooks.Account.self, configurations: ModelConfiguration(url: url))
            old.mainContext.insert(StoreBeforeBooks.Account(name: "Checking", initialBalance: 100))
            old.mainContext.insert(StoreBeforeBooks.Account(name: "Savings", initialBalance: 250))
            try old.mainContext.save()
        }

        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: ModelConfiguration(url: url)
        )
        let context = container.mainContext
        let book = try Books.prepare(in: context)

        let accounts = try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)]))
        #expect(accounts.map(\.name) == ["Checking", "Savings"])
        #expect(accounts.map(\.initialBalance) == [100, 250])
        #expect(accounts.allSatisfy { $0.book === book })
        #expect(accounts[0].syncID != accounts[1].syncID)
        #expect(book.name == "My Book")
    }

    // MARK: Per-book data

    /// Two books, each with a checking account and a "Food" category.
    private func twoBooks(in context: ModelContext) throws -> (personal: Book, household: Book) {
        let personal = Book(name: "Personal", createdAt: day(2026, 1, 1))
        let household = Book(name: "Household", createdAt: day(2026, 6, 1))
        context.insert(personal)
        context.insert(household)
        for (book, balance) in [(personal, Decimal(100)), (household, 1000)] {
            let checking = Account(name: "Checking", initialBalance: balance)
            context.insert(checking)
            checking.book = book
            let food = try Ledger.category(named: "Food", book: book, in: context)
            Ledger.addTransaction(.withdrawal, amount: 10, to: checking, payee: "Grocer", category: food, in: context)
        }
        try context.save()
        return (personal, household)
    }

    @Test func queriesAndTotalsArePerBook() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let (personal, household) = try twoBooks(in: context)

        let personalAccounts = try context.fetch(FetchDescriptor(predicate: Account.inBook(personal)))
        let householdAccounts = try context.fetch(FetchDescriptor(predicate: Account.inBook(household)))
        #expect(personalAccounts.reduce(0) { $0 + $1.balance } == 90)
        #expect(householdAccounts.reduce(0) { $0 + $1.balance } == 990)
        #expect(try context.fetchCount(FetchDescriptor(predicate: AccountTransaction.inBook(personal))) == 1)
        #expect(try context.fetchCount(FetchDescriptor(predicate: Category.inBook(household))) == 1)

        // Each book has its own "Food"; looking one up stays within the book.
        let personalFood = try #require(try Ledger.existingCategory(named: "food", book: personal, in: context))
        let householdFood = try #require(try Ledger.existingCategory(named: "food", book: household, in: context))
        #expect(personalFood !== householdFood)
        #expect(personalFood.book === personal)
    }

    @Test func newRecordsTakeTheirAccountsBook() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let (_, household) = try twoBooks(in: context)
        let checking = try #require(household.accounts?.first)
        let savings = Account(name: "Savings")
        context.insert(savings)
        savings.book = household

        let transfer = Ledger.addTransfer(amount: 50, from: checking, to: savings, in: context)
        #expect(transfer.outgoing.book === household && transfer.incoming.book === household)

        var goalDraft = GoalDraft(account: savings)
        goalDraft.name = "Roof"
        goalDraft.targetText = "5000"
        #expect(goalDraft.save(in: context)?.book === household)

        var budgetDraft = BudgetDraft()
        budgetDraft.name = "Everything"
        budgetDraft.amountText = "800"
        #expect(budgetDraft.save(book: household, in: context)?.book === household)

        var ruleDraft = RecurringDraft(account: checking, now: day(2026, 11, 1), calendar: utc)
        ruleDraft.payee = "Power"
        ruleDraft.amountText = "60"
        let rule = try #require(ruleDraft.save(in: context, now: day(2026, 11, 1), calendar: utc))
        #expect(rule.book === household)

        // The occurrences the scheduler adds are in the book too.
        try RecurringScheduler.addDue(in: context, now: day(2026, 11, 2), calendar: utc)
        #expect(rule.transactions?.first?.book === household)
    }

    // MARK: Choosing and deleting

    @Test func theCurrentBookFallsBackToTheOldest() throws {
        let container = try makeInMemoryContainer()
        let (personal, household) = try twoBooks(in: container.mainContext)
        let books = [personal, household]
        #expect(Books.current(id: household.syncID, in: books) === household)
        #expect(Books.current(id: "deleted", in: books) === personal)
        #expect(Books.current(id: nil, in: books) === personal)

        let settings = try #require(UserDefaults(suiteName: "BookTests"))
        settings.removePersistentDomain(forName: "BookTests")
        settings.set(household.syncID, forKey: Books.currentKey)
        #expect(try Books.current(in: container.mainContext, settings: settings) === household)
    }

    @Test func creatingNeedsAName() throws {
        let container = try makeInMemoryContainer()
        #expect(Books.create(named: "   ", in: container.mainContext) == nil)
        #expect(Books.create(named: " Trip ", in: container.mainContext)?.name == "Trip")
    }

    @Test func deletingABookDeletesOnlyWhatsInIt() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let (personal, household) = try twoBooks(in: context)

        #expect(try Books.delete(household, in: context))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Book>()).map(\.name) == ["Personal"])
        #expect(try context.fetch(FetchDescriptor<Account>()).allSatisfy { $0.book === personal })
        #expect(try context.fetchCount(FetchDescriptor<AccountTransaction>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Stirling_Money.Category>()) == 1)

        // There's always a book to show.
        #expect(try !Books.delete(personal, in: context))
    }
}
