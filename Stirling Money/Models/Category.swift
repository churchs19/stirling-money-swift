import Foundation
import SwiftData

@Model
final class Category {
    var name: String = ""
    /// When the category was created. Synced with the record, so every device agrees on which of two
    /// same-named categories is older when merging duplicates.
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \AccountTransaction.category)
    var transactions: [AccountTransaction]? = []

    /// A budget for a deleted category would silently turn into an "all spending" budget,
    /// so its budgets are deleted with it.
    @Relationship(deleteRule: .cascade, inverse: \Budget.category)
    var budgets: [Budget]? = []

    init(name: String) {
        self.name = name
    }
}
