import Foundation

/// How the accounts screen shows accounts. Remembered between launches.
nonisolated enum AccountLayout: String {
    case tiles
    case list

    /// The other layout, which the toolbar button switches to.
    var toggled: AccountLayout {
        self == .tiles ? .list : .tiles
    }

    /// The SF Symbol for this layout.
    var systemImage: String {
        switch self {
        case .tiles: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }

    /// The button title for switching to this layout.
    var switchTitle: String {
        switch self {
        case .tiles: String(localized: "Show as Tiles")
        case .list: String(localized: "Show as List")
        }
    }
}
