import Foundation
import os
import SwiftData

/// Creating, choosing and deleting books, and putting data from before books into one.
enum Books {
    /// The settings key holding the current book's `syncID`. Read it with `@AppStorage` or `LaunchMode.settings`.
    static let currentKey = "currentBookID"

    /// The name of the book made for existing data, or on a first launch.
    static var defaultName: String {
        String(localized: "My Book")
    }

    private static let log = Logger(subsystem: "net.s-church.stirlingmoney", category: "Books")

    /// Makes sure there's a book, and puts anything without one in the oldest book. Call at launch, before anything
    /// reads the data.
    ///
    /// Data saved before books existed has no book. Its `syncID`s are also all the same: the store's migration fills
    /// a new column with one default value for every row. So each such record gets a new `syncID` too.
    @discardableResult
    static func prepare(in context: ModelContext) throws -> Book {
        let book: Book
        if let oldest = try context.fetch(FetchDescriptor<Book>(sortBy: Book.order)).first {
            book = oldest
        } else {
            book = Book(name: defaultName)
            context.insert(book)
        }
        let moved = try adopt(Account.self, #Predicate { $0.book == nil }, into: book, in: context)
            + adopt(AccountTransaction.self, #Predicate { $0.book == nil }, into: book, in: context)
            + adopt(Category.self, #Predicate { $0.book == nil }, into: book, in: context)
            + adopt(Budget.self, #Predicate { $0.book == nil }, into: book, in: context)
            + adopt(Goal.self, #Predicate { $0.book == nil }, into: book, in: context)
            + adopt(RecurringTransaction.self, #Predicate { $0.book == nil }, into: book, in: context)
        if moved > 0 {
            log.notice("Put \(moved) records without a book into \(book.name, privacy: .private)")
        }
        if context.hasChanges {
            try context.save()
        }
        return book
    }

    /// Puts every `T` matching `predicate` (those without a book) into `book`, each with a new `syncID`.
    private static func adopt<T: PersistentModel & BookOwned>(
        _: T.Type, _ predicate: Predicate<T>, into book: Book, in context: ModelContext
    ) throws -> Int {
        let orphans = try context.fetch(FetchDescriptor<T>(predicate: predicate))
        for orphan in orphans {
            orphan.syncID = UUID().uuidString
            orphan.book = book
        }
        return orphans.count
    }

    /// The book with this `syncID`, or the oldest if it's gone (or none was chosen yet).
    static func current(id: String?, in books: [Book]) -> Book? {
        books.first { $0.syncID == id } ?? books.first
    }

    /// The current book, as saved in `settings`.
    static func current(in context: ModelContext, settings: UserDefaults) throws -> Book? {
        let books = try context.fetch(FetchDescriptor<Book>(sortBy: Book.order))
        return current(id: settings.string(forKey: currentKey), in: books)
    }

    /// Adds a book with this name. Returns nil for a blank name.
    @discardableResult
    static func create(named name: String, in context: ModelContext, now: Date = .now) -> Book? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let book = Book(name: trimmed, createdAt: now)
        context.insert(book)
        return book
    }

    /// Deletes a book and everything in it. The last book can't be deleted, so there's always one to show.
    /// Returns whether it was deleted.
    @discardableResult
    static func delete(_ book: Book, in context: ModelContext) throws -> Bool {
        guard try context.fetchCount(FetchDescriptor<Book>()) > 1 else { return false }
        context.delete(book)
        return true
    }
}

/// A model that belongs to a book.
protocol BookOwned: AnyObject {
    var syncID: String { get set }
    var book: Book? { get set }
}

extension Account: BookOwned {}
extension AccountTransaction: BookOwned {}
extension Category: BookOwned {}
extension Budget: BookOwned {}
extension Goal: BookOwned {}
extension RecurringTransaction: BookOwned {}
