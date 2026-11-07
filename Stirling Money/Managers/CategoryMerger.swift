import Foundation
import SwiftData

/// Combines categories that have the same name, ignoring case and surrounding spaces.
///
/// With iCloud sync, two devices can each create "Groceries" before they see each other's,
/// leaving two. The oldest one is kept and the others' transactions and budgets move to it.
/// Every device picks the same survivor, because `createdAt` syncs with the record.
enum CategoryMerger {
    /// Returns how many duplicate categories were merged away.
    @discardableResult
    static func mergeDuplicates(in context: ModelContext) throws -> Int {
        let categories = try context.fetch(FetchDescriptor<Category>())
        let groups = Dictionary(grouping: categories) {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        var merged = 0
        for (key, group) in groups where group.count > 1 && !key.isEmpty {
            let ordered = group.sorted(by: isPreferred)
            let keeper = ordered[0]
            for duplicate in ordered.dropFirst() {
                for transaction in duplicate.transactions ?? [] {
                    transaction.category = keeper
                }
                for budget in duplicate.budgets ?? [] {
                    budget.category = keeper
                }
                context.delete(duplicate)
                merged += 1
            }
        }
        if merged > 0 {
            try context.save()
        }
        return merged
    }

    /// The oldest first; for the same creation time, the name's exact spelling decides,
    /// so devices still agree.
    private static func isPreferred(_ lhs: Category, _ rhs: Category) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.name < rhs.name
    }
}
