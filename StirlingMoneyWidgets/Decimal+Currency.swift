import Foundation

extension FormatStyle where Self == Decimal.FormatStyle.Currency {
    /// Matches the app's currency format: the user's locale, falling back to US dollars.
    static var localCurrency: Self {
        .currency(code: Locale.current.currency?.identifier ?? "USD")
    }
}
