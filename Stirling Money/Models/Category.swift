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

    init(name: String) {
        self.name = name
    }
}
