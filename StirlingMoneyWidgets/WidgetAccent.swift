import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// The accent color chosen in the app's Settings, read from the App Group's user defaults.
/// Mirrors `AccentChoice` in `Stirling Money/Models/AccentChoice.swift`; **keep the keys and
/// stored values in step.**
enum WidgetAccent {
    /// The widgets' AccentColor asset, the same purple as the app's. Named directly because
    /// `Color.accentColor` is the system blue inside a widget.
    static let standard = Color("AccentColor")

    static var current: Color {
        let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroup)
        switch defaults?.string(forKey: "accentChoice") {
        case "system":
            #if os(macOS)
                return Color(nsColor: .controlAccentColor)
            #else
                return standard
            #endif
        case "custom":
            guard let text = defaults?.string(forKey: "accentCustomColor"),
                  let resolved = try? JSONDecoder().decode(Color.Resolved.self, from: Data(text.utf8))
            else { return standard }
            return Color(resolved)
        default:
            // "standard" or not set.
            return standard
        }
    }
}
