import SwiftUI

extension EnvironmentValues {
    /// The accent color chosen in Settings. Use it where a view would otherwise name
    /// `Color.accentColor`, which always means the default.
    @Entry var appAccent: Color = .accentColor
}

extension View {
    /// Tints this view and everything it presents with the accent color chosen in Settings.
    /// Apply it to each scene's root view.
    func appAccent() -> some View {
        modifier(AppAccentModifier())
    }
}

private struct AppAccentModifier: ViewModifier {
    @AppStorage(AccentChoice.key, store: AccentChoice.store) private var choice: AccentChoice = .standard
    @AppStorage(AccentChoice.customColorKey, store: AccentChoice.store) private var customColor = ""

    func body(content: Content) -> some View {
        let color = choice.color(customColor: customColor)
        content
            .tint(color)
            .environment(\.appAccent, color)
    }
}
