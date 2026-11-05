import SwiftUI

/// Modifiers that only exist on touch platforms (iOS, iPadOS, visionOS). On macOS they do nothing,
/// so views can use them without scattering `#if os(macOS)` checks.
extension View {
    /// Capitalizes each word as the user types, for names.
    func capitalizesWords() -> some View {
        #if os(macOS)
            self
        #else
            textInputAutocapitalization(.words)
        #endif
    }

    /// Shows a keyboard with digits, a decimal point and a minus sign, for money amounts.
    func amountKeyboard() -> some View {
        #if os(macOS)
            self
        #else
            keyboardType(.numbersAndPunctuation)
        #endif
    }

    /// A small centered title, for sheets. macOS sheets have no navigation bar title to size.
    func inlineNavigationTitle() -> some View {
        #if os(macOS)
            self
        #else
            navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Settings for a form shown in a sheet. On macOS, sections get the same grouped look as
    /// iOS instead of a bare two-column form, and the sheet gets a usable minimum size.
    func sheetForm() -> some View {
        #if os(macOS)
            formStyle(.grouped)
                .frame(minWidth: 400, minHeight: 280)
        #else
            formStyle(.grouped)
        #endif
    }
}
