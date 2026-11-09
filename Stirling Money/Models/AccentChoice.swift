import SwiftUI

/// Which accent color the app uses: its own purple, the system's, or one the person picks.
/// Stored per device in user defaults.
nonisolated enum AccentChoice: String, CaseIterable, Identifiable {
    /// The app's AccentColor asset (#7B2CBF; #9D4EDD in dark mode).
    case standard
    /// The Mac's accent color from System Settings. Only offered on the Mac:
    /// iPhone and iPad have no accent color setting.
    case system
    /// The color stored under `customColorKey`.
    case custom

    static let key = "accentChoice"
    static let customColorKey = "accentCustomColor"

    var id: Self { self }

    /// The choices Settings offers on this platform.
    static var available: [AccentChoice] {
        #if os(macOS)
            allCases
        #else
            [.standard, .custom]
        #endif
    }

    var title: LocalizedStringResource {
        switch self {
        case .standard: "Stirling Money"
        case .system: "System"
        case .custom: "Custom"
        }
    }

    /// The color for this choice. `customColor` is the stored custom color, if any;
    /// without one, Custom falls back to the default.
    func color(customColor: String) -> Color {
        switch self {
        case .standard:
            return .accentColor
        case .system:
            #if os(macOS)
                return Color(nsColor: .controlAccentColor)
            #else
                return .accentColor
            #endif
        case .custom:
            return Self.decode(customColor).map { Color($0) } ?? .accentColor
        }
    }

    // MARK: Storing the custom color

    /// The custom color as text for user defaults (`Color.Resolved` is Codable).
    static func encode(_ color: Color.Resolved) -> String {
        guard let data = try? JSONEncoder().encode(color) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ text: String) -> Color.Resolved? {
        guard !text.isEmpty else { return nil }
        return try? JSONDecoder().decode(Color.Resolved.self, from: Data(text.utf8))
    }
}
