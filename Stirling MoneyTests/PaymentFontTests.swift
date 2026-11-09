import CoreText
import Foundation
import Testing
@testable import Stirling_Money

struct PaymentFontTests {
    @Test func tableCoversTheWholeFontOnce() {
        #expect(PaymentFont.glyphs.count == 116)
        #expect(Set(PaymentFont.glyphs.map(\.id)).count == 116, "icon names are unique")
        // The font uses U+F000...U+F073 with no gaps.
        #expect(PaymentFont.glyphs.map(\.codePoint) == Array(0xF000 ... 0xF073))
    }

    @Test func bundledFontRegistersAndHasEveryGlyph() throws {
        #expect(PaymentFont.isRegistered, "the font is missing from the app bundle")
        let font = CTFontCreateWithName(PaymentFont.fontName as CFString, 20, nil)
        #expect((CTFontCopyPostScriptName(font) as String) == PaymentFont.fontName)

        let missing = PaymentFont.glyphs.filter { glyph in
            var characters = Array(glyph.character.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            return !CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count) || glyphs[0] == 0
        }
        #expect(missing.map(\.name) == [])
    }

    @Test func iconNamesResolveToGlyphsOrSymbols() {
        #expect(PaymentFont.glyph(forIconName: "pf-visa")?.codePoint == 0xF045)
        #expect(PaymentFont.glyph(forIconName: "pf-visa")?.displayName == "Visa")
        #expect(PaymentFont.glyph(forIconName: "pf-ideal")?.displayName == "iDEAL")
        #expect(PaymentFont.glyph(forIconName: "creditcard") == nil, "SF Symbol names aren't glyphs")
        #expect(PaymentFont.glyph(forIconName: "pf-not-a-glyph") == nil)
        // No SF Symbol choice can be mistaken for a glyph.
        #expect(Account.iconChoices.allSatisfy { !$0.hasPrefix(PaymentFont.iconNamePrefix) })
    }
}
