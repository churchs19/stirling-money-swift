import Foundation
import SwiftData

@Model
final class Account {
    var name: String = ""
    var initialBalance: Decimal = 0
    var createdAt: Date = Date.now
    /// An SF Symbol name shown on the account's tile, or nil for none. See `Account.iconChoices`.
    var iconName: String?

    @Relationship(deleteRule: .cascade, inverse: \AccountTransaction.account)
    var transactions: [AccountTransaction]? = []

    @Relationship(deleteRule: .cascade, inverse: \Goal.account)
    var goals: [Goal]? = []

    /// Recurring transactions added to this account; deleted with it.
    @Relationship(deleteRule: .cascade, inverse: \RecurringTransaction.account)
    var recurringTransactions: [RecurringTransaction]? = []

    /// Recurring transfers into this account from others. Deleting the account leaves them without a destination,
    /// and they stop until another is chosen.
    @Relationship(deleteRule: .nullify, inverse: \RecurringTransaction.otherAccount)
    var recurringTransfersIn: [RecurringTransaction]? = []

    init(name: String, initialBalance: Decimal = 0, iconName: String? = nil) {
        self.name = name
        self.initialBalance = initialBalance
        self.iconName = iconName
    }

    /// The icons offered in the account forms, as SF Symbol names.
    static let iconChoices = [
        "banknote", "creditcard", "building.columns", "dollarsign.circle",
        "wallet.pass", "chart.line.uptrend.xyaxis", "briefcase", "house",
        "car", "cart", "gift", "airplane",
        "graduationcap", "heart", "bag", "star",
    ]

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
