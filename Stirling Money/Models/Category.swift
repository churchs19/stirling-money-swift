import Foundation
import SwiftData

@Model
final class Category {
    var name: String = ""

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
