import Foundation

/// The transaction form's fields, kept as typed text until saved so a half-typed amount
/// never reaches the model. Save it with `Ledger.save(_:in:editing:context:)`.
struct TransactionDraft {
    var kind: TransactionKind = .withdrawal
    /// Entered without a sign; the kind decides whether money goes in or out.
    var amountText = ""
    var date = Date.now
    var payee = ""
    var note = ""
    var isPosted = false
    var checkNumberText = ""
    var category: Category?
    /// For a transfer, the account on the other side.
    var otherAccount: Account?
    /// True when money comes into the register's account from `otherAccount`.
    /// New transfers go out; an existing incoming half keeps its direction.
    var isIncomingTransfer = false

    /// A blank form for a new entry in `account`, with the check number filled in.
    init(account: Account) {
        checkNumberText = String(account.nextCheckNumber)
    }

    /// The form filled in from an existing entry.
    init(editing transaction: AccountTransaction) {
        kind = transaction.kind
        amountText = abs(transaction.amount).formatted(.localCurrency)
        date = transaction.date
        payee = transaction.payee
        note = transaction.note
        isPosted = transaction.isPosted
        category = transaction.category
        if let checkNumber = transaction.checkNumber {
            checkNumberText = String(checkNumber)
        } else if let account = transaction.account {
            checkNumberText = String(account.nextCheckNumber)
        }
        if transaction.kind == .transfer {
            otherAccount = transaction.transferCounterpart?.account
            isIncomingTransfer = transaction.amount > 0
        }
    }

    var trimmedPayee: String {
        payee.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The amount as a positive number, or nil if it's blank, zero or not a number.
    var amount: Decimal? {
        Decimal(positiveUserInput: amountText)
    }

    /// True when the amount field has text that can't be used, so the form can say so.
    /// A blank field isn't reported; Save is simply disabled.
    var hasInvalidAmount: Bool {
        !amountText.trimmingCharacters(in: .whitespaces).isEmpty && amount == nil
    }

    /// The check number, or nil when the field is blank or invalid.
    var checkNumber: Int? {
        guard let number = Int(checkNumberText.trimmingCharacters(in: .whitespaces)), number > 0 else { return nil }
        return number
    }

    /// A check number is optional, but if one is typed it must be a whole number above zero.
    var hasInvalidCheckNumber: Bool {
        !checkNumberText.trimmingCharacters(in: .whitespaces).isEmpty && checkNumber == nil
    }

    var isValid: Bool {
        guard amount != nil else { return false }
        switch kind {
        case .transfer:
            return otherAccount != nil
        case .check:
            return !trimmedPayee.isEmpty && !hasInvalidCheckNumber
        case .withdrawal, .deposit:
            return !trimmedPayee.isEmpty
        }
    }
}
