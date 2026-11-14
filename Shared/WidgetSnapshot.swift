import Foundation
import SwiftUI

/// What the widgets and the Watch show: a summary the app writes to the App Group folder as JSON,
/// because they can't open the SwiftData store. Shared by the app and the widget targets
/// (the `Shared/` folder). The app builds it from its models in `WidgetSnapshot+Models.swift`.
nonisolated struct WidgetSnapshot: Codable, Equatable {
    struct AccountSummary: Codable, Hashable, Identifiable {
        var id: String
        var name: String
        var balance: Decimal
        var postedBalance: Decimal
        /// The account's icon when it's an SF Symbol name.
        var iconSymbol: String? = nil
        /// The account's icon when it's a PaymentFont glyph: the glyph's character in that font.
        var iconGlyph: String? = nil
    }

    struct GoalSummary: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var accountName: String
        var currentAmount: Decimal
        var targetAmount: Decimal
        var progress: Double
        var targetDate: Date
    }

    /// A budget's current period, worked out on the iPhone. Only budgets in an active period are included.
    struct BudgetSummary: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        /// The category's name; nil for a budget that covers all spending.
        var categoryName: String?
        /// The limit for the period, as a positive amount.
        var amount: Decimal
        /// Spending in the period, as a positive amount.
        var spent: Decimal
        var periodStart: Date
        /// The start of the day after the period's last day.
        var periodEnd: Date

        /// Money left in the period; negative when over budget.
        var remaining: Decimal {
            amount - spent
        }

        var isOverBudget: Bool {
            spent > amount
        }

        /// Fraction of the budget spent, from 0 to 1.
        var progress: Double {
            guard amount > 0 else { return spent > 0 ? 1 : 0 }
            let fraction = NSDecimalNumber(decimal: spent / amount).doubleValue
            return min(max(fraction, 0), 1)
        }

        /// Whether these figures still describe the budget on `date`. Once the period is over,
        /// the iPhone has to send new ones; until then the amounts are last period's.
        func isCurrent(on date: Date) -> Bool {
            date >= periodStart && date < periodEnd
        }
    }

    var accounts: [AccountSummary]
    var goals: [GoalSummary]
    var budgets: [BudgetSummary] = []
    /// The custom accent color chosen on the iPhone; nil means Stirling Money's purple.
    var accentColor: Color.Resolved? = nil
    var updatedAt: Date

    static let appGroup = "group.net.s-church.stirlingmoney"
    static let fileName = "WidgetSnapshot.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: fileName)
    }

    /// The latest snapshot, or nil if the app hasn't written one yet.
    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    var total: Decimal {
        accounts.reduce(0) { $0 + $1.balance }
    }

    static let sample = WidgetSnapshot(
        accounts: [
            AccountSummary(id: "checking", name: "Checking", balance: 1250.75, postedBalance: 1180.25, iconSymbol: "building.columns"),
            AccountSummary(id: "savings", name: "Savings", balance: 8500, postedBalance: 8500),
        ],
        goals: [
            GoalSummary(
                id: "fund", name: "Emergency Fund", accountName: "Savings", currentAmount: 8500,
                targetAmount: 15000, progress: 0.07, targetDate: .now.addingTimeInterval(86400 * 200)
            ),
        ],
        budgets: [
            BudgetSummary(
                id: "food", name: "Food", categoryName: "Groceries", amount: 400, spent: 275,
                periodStart: Calendar.current.startOfDay(for: .now.addingTimeInterval(-86400 * 10)),
                periodEnd: Calendar.current.startOfDay(for: .now.addingTimeInterval(86400 * 20))
            ),
            BudgetSummary(
                id: "fun", name: "Fun", categoryName: nil, amount: 150, spent: 180,
                periodStart: Calendar.current.startOfDay(for: .now.addingTimeInterval(-86400 * 3)),
                periodEnd: Calendar.current.startOfDay(for: .now.addingTimeInterval(86400 * 4))
            ),
        ],
        updatedAt: .now
    )
}

extension WidgetSnapshot {
    /// Decodes snapshots written before budgets and the accent color were added, too.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try container.decode([AccountSummary].self, forKey: .accounts)
        goals = try container.decode([GoalSummary].self, forKey: .goals)
        budgets = try container.decodeIfPresent([BudgetSummary].self, forKey: .budgets) ?? []
        accentColor = try container.decodeIfPresent(Color.Resolved.self, forKey: .accentColor)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
