import Foundation

/// What a widget or complication set to one goal or budget shows. Every one of them follows the same rule:
/// none chosen yet means the first, and a chosen one that's gone gets a message rather than another item.
nonisolated enum WidgetChoice<Item: Identifiable & Equatable>: Equatable where Item.ID == String {
    case item(Item)
    /// The app hasn't written a summary yet.
    case noSummary
    /// There are none of these yet.
    case noneExist
    /// The chosen one was deleted (or, for a budget, its period ended and the app left it out).
    case missing

    /// The item to show, if there is one.
    var item: Item? {
        if case let .item(item) = self {
            item
        } else {
            nil
        }
    }

    /// Picks the item with `id` from `items`, or the first when `id` is nil. `items` is nil when there's no summary.
    static func choose(id: String?, from items: [Item]?) -> WidgetChoice {
        guard let items else { return .noSummary }
        guard let id else { return items.first.map(Self.item) ?? .noneExist }
        return items.first { $0.id == id }.map(Self.item) ?? .missing
    }
}

/// What a Balance widget or complication shows. Unlike goals and budgets, none chosen means the total of all accounts.
nonisolated enum BalanceChoice: Equatable {
    case total
    case account(WidgetSnapshot.AccountSummary)
    /// The app hasn't written a summary yet.
    case noSummary
    /// The chosen account was deleted.
    case missing

    static func choose(accountID: String?, in snapshot: WidgetSnapshot?) -> BalanceChoice {
        guard let snapshot else { return .noSummary }
        guard let accountID else { return .total }
        return snapshot.accounts.first { $0.id == accountID }.map(Self.account) ?? .missing
    }
}
