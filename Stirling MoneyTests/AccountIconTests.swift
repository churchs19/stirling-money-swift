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

    @Test(arguments: [AccountLayout.tiles, .list])
    func layoutSymbolIsARealSymbol(_ layout: AccountLayout) {
        #if canImport(UIKit)
            #expect(UIImage(systemName: layout.systemImage) != nil)
        #else
            #expect(NSImage(systemSymbolName: layout.systemImage, accessibilityDescription: nil) != nil)
        #endif
    }

    @Test func layoutAndSortKeepTheirStoredNames() {
        // These are saved in the settings; renaming a case would reset everyone's choice.
        #expect(AccountLayout(rawValue: "tiles") == .tiles)
        #expect(AccountLayout(rawValue: "list") == .list)
        #expect(AccountSort(rawValue: "name") == .name)
        #expect(AccountSort(rawValue: "mostUsed") == .mostUsed)
        #expect(AccountSort.allCases.count == 2)
    }

    @Test func layoutAndSortHaveDistinctLabels() {
        #expect(AccountLayout.tiles.switchTitle != AccountLayout.list.switchTitle)
        #expect(AccountLayout.tiles.systemImage != AccountLayout.list.systemImage)
        #expect(Set(AccountSort.allCases.map(\.title)).count == AccountSort.allCases.count)
        #expect(AccountSort.allCases.allSatisfy { !$0.title.isEmpty })
    }
}
