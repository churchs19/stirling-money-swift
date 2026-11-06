import Foundation

/// Links into the app, such as from a widget: `stirlingmoney://account?id=<widget ID>`.
/// The widget builds the same URL in `StirlingMoneyWidgets/BalanceWidget.swift`; keep them in step.
nonisolated enum DeepLink: Equatable {
    /// An account's register. The ID is `WidgetSnapshot.widgetID(for:)`.
    case account(id: String)

    static let scheme = "stirlingmoney"

    init?(url: URL) {
        guard url.scheme == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "account",
              let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
              !id.isEmpty
        else { return nil }
        self = .account(id: id)
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case let .account(id):
            components.host = "account"
            components.queryItems = [URLQueryItem(name: "id", value: id)]
        }
        return components.url!
    }
}
