import Foundation
import SwiftData

/// A set of accounts with their own categories, budgets, goals and recurring transactions, such as a household's
/// shared finances kept apart from personal ones. A book is the unit of sharing (Phase 11): everything in it is synced
/// to one CloudKit zone, and transfers, goals and budgets never reach outside it.
///
/// The sharing fields are a local copy of what CloudKit says, for showing and enforcing permissions. Until sync is
/// built, every book is the user's own and editable.
@Model
final class Book {
    var name: String = ""
    var createdAt: Date = Date.now
    /// The book's identity across devices; its CloudKit zone is named after it. Kept on deletion so the history
    /// tombstone says which zone to delete.
    @Attribute(.preserveValueOnDeletion)
    var syncID: String = UUID().uuidString

    /// Whether the book is shared with anyone (as owner or participant).
    var isShared: Bool = false
    /// False for a book someone else shared with this user.
    var isOwnedByMe: Bool = true
    /// False for a view-only participant.
    var canEdit: Bool = true
    /// The owner's name, for a book shared with this user.
    var ownerName: String?
    /// The CloudKit user record name of the zone's owner, for a book shared with this user. nil for the user's own
    /// books (`CKCurrentUserDefaultName`).
    var zoneOwnerName: String?
    /// The book record's system fields from the last sync. See `Account.ckSystemFields`.
    var ckSystemFields: Data?

    @Relationship(deleteRule: .cascade, inverse: \Account.book)
    var accounts: [Account]? = []
    @Relationship(deleteRule: .cascade, inverse: \Category.book)
    var categories: [Category]? = []
    @Relationship(deleteRule: .cascade, inverse: \Budget.book)
    var budgets: [Budget]? = []
    @Relationship(deleteRule: .cascade, inverse: \Goal.book)
    var goals: [Goal]? = []
    @Relationship(deleteRule: .cascade, inverse: \RecurringTransaction.book)
    var recurringTransactions: [RecurringTransaction]? = []
    @Relationship(deleteRule: .cascade, inverse: \AccountTransaction.book)
    var transactions: [AccountTransaction]? = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }

    /// Books in the switcher's order: oldest first, so the first book stays first.
    static let order = [SortDescriptor(\Book.createdAt), SortDescriptor(\Book.name)]
}

// MARK: - Per-book queries

// One predicate per model, since `#Predicate` can't be written over a protocol. Each matches the models in `book`
// (or, for nil, those in no book).

extension Account {
    static func inBook(_ book: Book?) -> Predicate<Account> {
        let id = book?.syncID
        return #Predicate { $0.book?.syncID == id }
    }
}

extension AccountTransaction {
    static func inBook(_ book: Book?) -> Predicate<AccountTransaction> {
        let id = book?.syncID
        return #Predicate { $0.book?.syncID == id }
    }
}

extension Category {
    static func inBook(_ book: Book?) -> Predicate<Category> {
        let id = book?.syncID
        return #Predicate { $0.book?.syncID == id }
    }
}

extension Budget {
    static func inBook(_ book: Book?) -> Predicate<Budget> {
        let id = book?.syncID
        return #Predicate { $0.book?.syncID == id }
    }
}

extension Goal {
    static func inBook(_ book: Book?) -> Predicate<Goal> {
        let id = book?.syncID
        return #Predicate { $0.book?.syncID == id }
    }
}

extension RecurringTransaction {
    static func inBook(_ book: Book?) -> Predicate<RecurringTransaction> {
        let id = book?.syncID
        return #Predicate { $0.book?.syncID == id }
    }
}
