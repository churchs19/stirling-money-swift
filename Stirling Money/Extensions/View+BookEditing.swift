import SwiftUI

extension EnvironmentValues {
    /// Whether the current book can be changed: false for a book someone shared with the user as View Only.
    /// `RootView` sets it for each tab; sheets inherit it. Editing controls hide or disable themselves when false.
    @Entry var canEditBook: Bool = true
}
