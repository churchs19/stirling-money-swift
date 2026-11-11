import Foundation

// `.localCurrency` is in Shared/Decimal+Currency.swift, so the widgets and the Watch format money the same way.

nonisolated extension Decimal {
    /// Parses an amount typed by the user in their locale's number format, with or without
    /// the currency symbol ("1250.75" or "$1,250.75"), so text shown with `.localCurrency` parses back.
    /// Blank text means zero; returns nil when the text isn't a number.
    init?(userInput text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            self = 0
            return
        }
        // The currency style also reads plain numbers. The plain number style can't be tried
        // first: it reads "-$1,250.75" as 0 instead of failing.
        guard let value = try? Decimal(trimmed, format: .localCurrency) else { return nil }
        self = value
    }

    /// Parses an amount that must be above zero, such as a transaction or budget amount.
    /// A typed minus sign is ignored; blank, zero or non-numeric text returns nil.
    init?(positiveUserInput text: String) {
        guard let value = Decimal(userInput: text), value != 0 else { return nil }
        self = abs(value)
    }

    /// The amount as plain editable text, without grouping separators ("1250.75").
    var editableText: String {
        formatted(.number.grouping(.never))
    }
}
