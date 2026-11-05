import Foundation

extension FormatStyle where Self == Decimal.FormatStyle.Currency {
    /// Currency in the user's locale, falling back to US dollars.
    static var localCurrency: Self {
        .currency(code: Locale.current.currency?.identifier ?? "USD")
    }
}

nonisolated extension Decimal {
    /// Parses an amount typed by the user in their locale's number format.
    /// Blank text means zero; returns nil when the text isn't a number.
    init?(userInput text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            self = 0
            return
        }
        guard let value = try? Decimal(trimmed, format: .number) else { return nil }
        self = value
    }

    /// The amount as plain editable text, without grouping separators ("1250.75").
    var editableText: String {
        formatted(.number.grouping(.never))
    }
}
