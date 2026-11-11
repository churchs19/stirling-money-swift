import Foundation

/// What the widgets (and, later, the Watch) show: a summary the app writes to the App Group folder
/// as JSON, because they can't open the SwiftData store. Shared by the app and the widget targets
/// (the `Shared/` folder). The app builds it from its models in `WidgetSnapshot+Models.swift`.
nonisolated struct WidgetSnapshot: Codable, Equatable {
    struct AccountSummary: Codable, Equatable, Identifiable {
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

    var accounts: [AccountSummary]
    var goals: [GoalSummary]
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
        updatedAt: .now
    )
}
