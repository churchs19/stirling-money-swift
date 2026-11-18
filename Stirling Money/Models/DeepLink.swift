import Foundation

/// Links into the app from the widgets: `stirlingmoney://account?id=<widget ID>`, `stirlingmoney://goals` and
/// `stirlingmoney://budgets`. The widgets build the same URLs in `StirlingMoneyWidgets/BalanceWidget.swift`,
/// `GoalWidget.swift` and `BudgetWidget.swift`;
/// keep them in step.
nonisolated enum DeepLink: Equatable {
    /// An account's register. The ID is `WidgetSnapshot.widgetID(for:)`.
    case account(id: String)
    /// The Goals tab.
    case goals
    /// The Budgets tab.
    case budgets

    static let scheme = "stirlingmoney"

    init?(url: URL) {
        guard url.scheme == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        switch components.host {
        case "account":
            guard let id = components.queryItems?.first(where: { $0.name == "id" })?.value, !id.isEmpty else { return nil }
            self = .account(id: id)
        case "goals":
            self = .goals
        case "budgets":
            self = .budgets
        default:
            return nil
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case let .account(id):
            components.host = "account"
            components.queryItems = [URLQueryItem(name: "id", value: id)]
        case .goals:
            components.host = "goals"
        case .budgets:
            components.host = "budgets"
        }
        return components.url!
    }
}

extension DeepLink {
    /// The account an account link opens, or nil when it was deleted (the link then opens the accounts list).
    static func account(withWidgetID id: String, in accounts: [Account]) -> Account? {
        accounts.first { WidgetSnapshot.widgetID(for: $0) == id }
    }
}
