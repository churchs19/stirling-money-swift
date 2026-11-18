import Foundation

nonisolated extension FormatStyle where Self == Decimal.FormatStyle.Currency {
    /// Currency in the user's locale, falling back to US dollars. Used by the app, the widgets and the Watch.
    static var localCurrency: Self {
        localCurrency(in: .current)
    }

    /// Currency as `locale` writes it (its currency, symbol, separators and decimals). Tests pass other locales.
    static func localCurrency(in locale: Locale) -> Self {
        .currency(code: locale.currency?.identifier ?? "USD").locale(locale)
    }
}
