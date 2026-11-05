import Foundation
import SwiftData

@Model
final class Account {
    var name: String = ""
    var initialBalance: Decimal = 0
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \AccountTransaction.account)
    var transactions: [AccountTransaction]? = []

    @Relationship(deleteRule: .cascade, inverse: \Goal.account)
    var goals: [Goal]? = []

    init(name: String, initialBalance: Decimal = 0) {
        self.name = name
        self.initialBalance = initialBalance
    }

    /// Initial balance plus every transaction, posted or not.
    var balance: Decimal {
        initialBalance + (transactions ?? []).reduce(0) { $0 + $1.amount }
    }

    /// Initial balance plus only the transactions that have cleared the bank.
    var postedBalance: Decimal {
        initialBalance + (transactions ?? []).filter(\.isPosted).reduce(0) { $0 + $1.amount }
    }

    /// Used to sort accounts by "most frequently used".
    var transactionCount: Int {
        transactions?.count ?? 0
    }

    /// One past the highest check number written from this account, or 1 if none.
    var nextCheckNumber: Int {
        ((transactions ?? []).compactMap(\.checkNumber).max() ?? 0) + 1
    }
}
