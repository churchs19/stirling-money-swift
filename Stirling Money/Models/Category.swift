import Foundation
import SwiftData

@Model
final class Category {
    /// Its identity across devices (the CloudKit record name). Kept on deletion so the history tombstone says what
    /// was deleted.
    @Attribute(.preserveValueOnDeletion)
    var syncID: String = UUID().uuidString
    /// The book it belongs to. Set when it's created; see `Books`.
    var book: Book?
    /// The CloudKit record's system fields (change tag and so on) from the last sync, so the next save is checked
    /// against the server's copy. nil until first synced.
    var ckSystemFields: Data?

    var name: String = ""
    /// When two devices make a category with the same name, the copies are merged into the oldest.
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \AccountTransaction.category)
    var transactions: [AccountTransaction]? = []

    /// A budget for a deleted category would silently turn into an "all spending" budget,
    /// so its budgets are deleted with it.
    @Relationship(deleteRule: .cascade, inverse: \Budget.category)
    var budgets: [Budget]? = []

    /// Recurring transactions in this category keep repeating, uncategorized, when it's deleted.
    @Relationship(deleteRule: .nullify, inverse: \RecurringTransaction.category)
    var recurringTransactions: [RecurringTransaction]? = []

    init(name: String) {
        self.name = name
    }
}
