import Foundation
import SwiftData

nonisolated enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case withdrawal
    case deposit
    case check
    case transfer

    var id: Self {
        self
    }
}

/// A single register entry. Named `AccountTransaction` to avoid clashing with `SwiftUI.Transaction`.
///
/// `amount` is signed: negative money leaves the account, positive money comes in.
/// A transfer is stored as two linked entries, one in each account, joined by `transferCounterpart`.
/// Create and delete entries through `Ledger` so signs and transfer pairs stay consistent.
@Model
final class AccountTransaction {
    var date: Date = Date.now
    var amount: Decimal = 0
    var payee: String = ""
    var note: String = ""
    var isPosted: Bool = false
    var checkNumber: Int?
    var kindRawValue: String = TransactionKind.withdrawal.rawValue

    var account: Account?
    var category: Category?

    // A property can't be its own inverse, so a transfer pair uses two properties that are
    // each other's inverse: the outgoing half sets `incomingHalf`, and SwiftData fills in
    // `outgoingHalf` on the incoming half. Read `transferCounterpart` rather than either one.
    @Relationship(deleteRule: .nullify, inverse: \AccountTransaction.outgoingHalf)
    var incomingHalf: AccountTransaction?
    var outgoingHalf: AccountTransaction?

    /// The other half of a transfer, whichever side this is.
    var transferCounterpart: AccountTransaction? {
        incomingHalf ?? outgoingHalf
    }

    init(
        kind: TransactionKind,
        amount: Decimal,
        date: Date = .now,
        payee: String = "",
        note: String = "",
        isPosted: Bool = false,
        checkNumber: Int? = nil
    ) {
        kindRawValue = kind.rawValue
        self.amount = amount
        self.date = date
        self.payee = payee
        self.note = note
        self.isPosted = isPosted
        self.checkNumber = checkNumber
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRawValue) ?? .withdrawal }
        set { kindRawValue = newValue.rawValue }
    }

    /// The payee for display. Transfers name the other account, so renaming an account updates them.
    var displayPayee: String {
        guard kind == .transfer else { return payee }
        // Deleting an account keeps the other account's half, so its balance doesn't change.
        guard let otherName = transferCounterpart?.account?.name else {
            return amount < 0
                ? String(localized: "Transfer to a deleted account")
                : String(localized: "Transfer from a deleted account")
        }
        return amount < 0
            ? String(localized: "Transfer to \(otherName)")
            : String(localized: "Transfer from \(otherName)")
    }
}
