import SwiftUI

/// Colors for charts. The categorical palette is a validated reference palette: its order keeps
/// neighboring colors apart for color-blind readers, so assign slots in order and never cycle them.
/// A ninth series folds into "Other" instead of getting a new color.
///
/// Checked against the system grouped-list cells (white / #1C1C1E): every check passes, but three
/// light-mode colors are below 3:1 contrast with white, so every chart also lists its values as text.
enum ChartPalette {
    static let series: [Color] = [
        Color(light: 0x2A78D6, dark: 0x3987E5), // blue
        Color(light: 0xEB6834, dark: 0xD95926), // orange
        Color(light: 0x1BAF7A, dark: 0x199E70), // aqua
        Color(light: 0xEDA100, dark: 0xC98500), // yellow
        Color(light: 0xE87BA4, dark: 0xD55181), // magenta
        Color(light: 0x008300, dark: 0x008300), // green
        Color(light: 0x6250D6, dark: 0x9085E9), // violet
        Color(light: 0xE34948, dark: 0xE66767), // red
    ]

    /// For "Other": a neutral gray, so it never reads as one more category.
    static let other = Color(light: 0x9A9994, dark: 0x7C7B76)

    static func color(slot: Int?) -> Color {
        guard let slot, series.indices.contains(slot) else { return other }
        return series[slot]
    }
}

extension Color {
    /// A color with separate light and dark appearance values, given as 0xRRGGBB.
    init(light: UInt32, dark: UInt32) {
        #if os(macOS)
            self.init(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(Color(hex: isDark ? dark : light))
            })
        #else
            self.init(uiColor: UIColor { traits in
                UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
            })
        #endif
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
