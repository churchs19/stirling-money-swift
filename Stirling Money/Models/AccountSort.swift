import Foundation

nonisolated enum AccountSort: String, CaseIterable, Identifiable {
    case name
    case mostUsed

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .mostUsed: String(localized: "Most Used")
        }
    }
}

extension AccountSort {
    /// Most-used puts accounts with the most transactions first; ties fall back to name order.
    func sorted(_ accounts: [Account]) -> [Account] {
        accounts.sorted { lhs, rhs in
            if self == .mostUsed, lhs.transactionCount != rhs.transactionCount {
                return lhs.transactionCount > rhs.transactionCount
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
