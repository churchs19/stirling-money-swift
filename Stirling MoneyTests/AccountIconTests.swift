import Foundation
import Testing
@testable import Stirling_Money
#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

@MainActor
struct AccountIconTests {
    /// A misspelled SF Symbol shows as a blank square, so check every choice exists.
    @Test(arguments: Account.iconChoices)
    func iconChoiceIsARealSymbol(_ name: String) {
        #if canImport(UIKit)
            #expect(UIImage(systemName: name) != nil)
        #else
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
        #endif
    }

    @Test func iconChoicesAreUnique() {
        #expect(Set(Account.iconChoices).count == Account.iconChoices.count)
    }

    @Test func layoutTogglesBetweenTilesAndList() {
        #expect(AccountLayout.tiles.toggled == .list)
        #expect(AccountLayout.list.toggled == .tiles)
    }
}
