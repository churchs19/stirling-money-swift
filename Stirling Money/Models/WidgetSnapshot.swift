import Foundation
import SwiftData

/// What the widgets show, written by the app to the shared App Group folder as JSON.
/// The widget extension reads it with its own copy of this type, because it can't open the
/// SwiftData store. **Keep `StirlingMoneyWidgets/WidgetSnapshot.swift` in step with this file.**
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
}

extension WidgetSnapshot {
    /// A snapshot of the given accounts and goals, sorted by name.
    init(accounts: [Account], goals: [Goal], now: Date = .now) {
        self.accounts = AccountSort.name.sorted(accounts).map { account in
            var summary = AccountSummary(
                id: Self.widgetID(for: account), name: account.name,
                balance: account.balance, postedBalance: account.postedBalance
            )
            // The widget has the font but not the glyph table, so it gets the character itself.
            if let iconName = account.iconName {
                if let glyph = PaymentFont.glyph(forIconName: iconName) {
                    summary.iconGlyph = glyph.character
                } else {
                    summary.iconSymbol = iconName
                }
            }
            return summary
        }
        self.goals = goals
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map {
                GoalSummary(
                    id: Self.widgetID(for: $0),
                    name: $0.name,
                    accountName: $0.account?.name ?? "",
                    currentAmount: $0.currentAmount,
                    targetAmount: $0.targetAmount,
                    progress: $0.progress,
                    targetDate: $0.targetDate
                )
            }
        updatedAt = now
    }

    /// A stable string for a saved model, so a widget configured for an account keeps
    /// showing it after renames. Built from SwiftData's persistent identifier.
    static func widgetID(for model: some PersistentModel) -> String {
        // Sorted keys: otherwise the encoded key order varies between calls, and so would the ID.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(model.persistentModelID) else { return "" }
        return data.base64EncodedString()
    }
}
