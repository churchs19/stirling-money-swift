import SwiftUI
import Testing
@testable import Stirling_Money

struct AccentChoiceTests {
    @Test func customColorRoundTrips() throws {
        let color = Color.Resolved(red: 0.2, green: 0.6, blue: 0.4)
        let text = AccentChoice.encode(color)
        #expect(!text.isEmpty)
        let decoded = try #require(AccentChoice.decode(text))
        // JSON can lose the last bit of a Float, so compare closely rather than exactly.
        for (a, b) in [(decoded.red, color.red), (decoded.green, color.green), (decoded.blue, color.blue), (decoded.opacity, color.opacity)] {
            #expect(abs(a - b) < 0.0001)
        }
    }

    @Test func missingOrBadCustomColorFallsBackToTheDefault() {
        #expect(AccentChoice.decode("") == nil)
        #expect(AccentChoice.decode("not json") == nil)
        #expect(AccentChoice.custom.color(customColor: "") == .accentColor)
    }

    @Test func systemIsOfferedOnlyOnTheMac() {
        #if os(macOS)
            #expect(AccentChoice.available == [.standard, .system, .custom])
        #else
            #expect(AccentChoice.available == [.standard, .custom])
            #expect(AccentChoice.system.color(customColor: "") == .accentColor, "falls back to the default")
        #endif
    }

    @Test func storedNamesStayTheSame() {
        // Raw values are saved in user defaults; renaming one would reset people's choice.
        #expect(AccentChoice.allCases.map(\.rawValue) == ["standard", "system", "custom"])
    }
}
