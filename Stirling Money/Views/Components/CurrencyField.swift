import SwiftUI

/// A labeled amount field that shows currency ("$1,450.00") while not being edited, and a plain
/// number ("1450") while it is, so there's no symbol or grouping to type around.
/// Parse the text with `Decimal(userInput:)` or `Decimal(positiveUserInput:)`.
struct CurrencyField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    /// When false, a typed minus sign is dropped when the field is formatted.
    var allowsNegative = false
    /// The text field's accessibility identifier, for UI tests.
    var identifier: String?

    @FocusState private var isFocused: Bool

    init(_ title: LocalizedStringKey, text: Binding<String>, allowsNegative: Bool = false, identifier: String? = nil) {
        self.title = title
        _text = text
        self.allowsNegative = allowsNegative
        self.identifier = identifier
    }

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text, prompt: Text(Decimal.zero.formatted(.localCurrency)))
                .accessibilityIdentifier(identifier ?? "")
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .amountKeyboard()
                .focused($isFocused)
                .onChange(of: isFocused) { _, isFocused in
                    guard !text.trimmingCharacters(in: .whitespaces).isEmpty,
                          var value = Decimal(userInput: text)
                    else { return }
                    if !allowsNegative {
                        value = abs(value)
                    }
                    text = isFocused ? value.editableText : value.formatted(.localCurrency)
                }
        }
    }
}

#Preview {
    @Previewable @State var text = "1450"
    Form {
        CurrencyField("Amount", text: $text)
    }
}
