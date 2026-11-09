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

    /// Shows a keyboard with digits only, for whole numbers such as check numbers.
    func numberKeyboard() -> some View {
        #if os(macOS)
            self
        #else
            keyboardType(.numberPad)
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

/// Runs a context-menu action that shows a sheet, alert or confirmation once the menu has closed.
///
/// On the Mac, a presentation started while the context menu is still closing is dropped. A `Task`
/// isn't late enough: the main queue keeps running during menu tracking. So the action waits until
/// the run loop is back in its default mode, which only happens once menu tracking has ended.
/// Elsewhere it runs straight away.
@MainActor
func afterMenuCloses(_ action: @escaping @MainActor () -> Void) {
    #if os(macOS)
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated { action() }
        }
    #else
        action()
    #endif
}

extension Color {
    /// The page behind a grouped list: light gray on iPhone and iPad, the list background on the Mac.
    /// Use it behind custom layouts (like account tiles) that sit beside a `List`, so switching between
    /// them doesn't change the colors.
    static var groupedPageBackground: Color {
        #if os(macOS)
            Color(nsColor: .controlBackgroundColor)
        #else
            Color(uiColor: .systemGroupedBackground)
        #endif
    }

    /// A card or row on `groupedPageBackground`: white rows on iPhone and iPad (dark gray in dark mode).
    /// Mac lists have no row background, so a subtle fill marks the card instead.
    static var groupedItemBackground: Color {
        #if os(macOS)
            Color(nsColor: .quaternaryLabelColor).opacity(0.5)
        #else
            Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}
