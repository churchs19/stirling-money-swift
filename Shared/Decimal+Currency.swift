import Foundation

nonisolated extension FormatStyle where Self == Decimal.FormatStyle.Currency {
    /// Currency in the user's locale, falling back to US dollars. Used by the app, the widgets and the Watch.
    static var localCurrency: Self {
        .currency(code: Locale.current.currency?.identifier ?? "USD")
    }
}
