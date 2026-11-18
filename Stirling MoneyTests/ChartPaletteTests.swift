import SwiftUI
import Testing
@testable import Stirling_Money

/// The report charts' colors (`ChartPalette`): slots in order, never cycled, and gray for "Other".
@MainActor
struct ChartPaletteTests {
    @Test func slotsUseThePaletteInOrder() {
        #expect(ChartPalette.series.count == 8)
        for slot in ChartPalette.series.indices {
            #expect(ChartPalette.color(slot: slot) == ChartPalette.series[slot])
        }
    }

    @Test func anythingPastThePaletteIsOtherNotACycledColor() {
        #expect(ChartPalette.color(slot: nil) == ChartPalette.other)
        #expect(ChartPalette.color(slot: 8) == ChartPalette.other, "a ninth series folds into Other")
        #expect(ChartPalette.color(slot: -1) == ChartPalette.other)
    }

    @Test func hexColorsHaveTheGivenComponents() {
        let resolved = Color(hex: 0x2A78D6).resolve(in: EnvironmentValues())
        #expect(abs(Double(resolved.red) - 0x2A / 255.0) < 0.01)
        #expect(abs(Double(resolved.green) - 0x78 / 255.0) < 0.01)
        #expect(abs(Double(resolved.blue) - 0xD6 / 255.0) < 0.01)
    }

    @Test func lightAndDarkColorsFollowTheColorScheme() {
        var light = EnvironmentValues()
        light.colorScheme = .light
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        // Blue: 0x2A78D6 in light mode, 0x3987E5 in dark mode.
        let blue = ChartPalette.series[0]
        #expect(abs(Double(blue.resolve(in: light).red) - 0x2A / 255.0) < 0.01)
        #expect(abs(Double(blue.resolve(in: dark).red) - 0x39 / 255.0) < 0.01)
    }
}
