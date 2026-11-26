import Foundation
import SwiftData

/// Combines categories in the same book that have the same name, ignoring case and surrounding spaces.
///
/// With iCloud sync, two devices (or two people sharing a book) can each create "Groceries" before they see each
/// other's, leaving two. The oldest is kept, and the others' transactions, budgets and recurring transactions move
/// to it before they're deleted. Every device picks the same one: `createdAt` syncs with the record, and ties fall
/// to the name's exact spelling, then the `syncID`.
///
/// Run after applying fetched records, saved as this device's own change so the merge is sent too; another device
/// merging at the same time makes the same change. View Only books are left to their owner's devices.
enum CategoryMerger {
    /// Merges duplicates in every book this user can edit. Returns how many categories were merged away. Doesn't
    /// save.
    @discardableResult
    static func mergeDuplicates(in context: ModelContext) throws -> Int {
        let categories = try context.fetch(FetchDescriptor<Category>())
        let groups = Dictionary(grouping: categories) { category in
            Key(bookID: category.book?.syncID, name: category.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }

        var merged = 0
        for (key, group) in groups where group.count > 1 && !key.name.isEmpty {
            guard group.first?.book?.canEdit != false else { continue }
            let ordered = group.sorted(by: isPreferred)
            let keeper = ordered[0]
            for duplicate in ordered.dropFirst() {
                for transaction in duplicate.transactions ?? [] {
                    transaction.category = keeper
                }
                for budget in duplicate.budgets ?? [] {
                    budget.category = keeper
                }
                for rule in duplicate.recurringTransactions ?? [] {
                    rule.category = keeper
                }
                replacements[duplicate.persistentModelID] = keeper
                context.delete(duplicate)
                merged += 1
            }
        }
        return merged
    }

    /// The category that took each merged-away one's place, for forms still holding the old one.
    private static var replacements: [PersistentIdentifier: Category] = [:]

    /// The category to save for `category`: the one it was merged into, if a merge removed it while a form was open
    /// (a merge runs whenever another device's categories arrive), otherwise itself.
    static func survivor(of category: Category?) -> Category? {
        guard let category else { return nil }
        var current = category
        while let keeper = replacements[current.persistentModelID] {
            current = keeper
        }
        return current
    }

    private struct Key: Hashable {
        let bookID: String?
        let name: String
    }

    /// The oldest first; for the same creation time, the name's exact spelling, then the `syncID`, so devices agree.
    private static func isPreferred(_ lhs: Category, _ rhs: Category) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }
        return lhs.syncID < rhs.syncID
    }
}
