import Foundation
import SwiftData

/// Creates and deletes register entries so amounts get the right sign and transfers stay paired.
enum Ledger {
    /// Adds a withdrawal, deposit or check. `amount` may be entered either sign;
    /// the kind decides the stored sign. Use `addTransfer` for transfers.
    @discardableResult
    static func addTransaction(
        _ kind: TransactionKind,
        amount: Decimal,
        to account: Account,
        date: Date = .now,
        payee: String,
        note: String = "",
        isPosted: Bool = false,
        checkNumber: Int? = nil,
        category: Category? = nil,
        in context: ModelContext
    ) -> AccountTransaction {
        precondition(kind != .transfer, "Use Ledger.addTransfer for transfers")
        let magnitude = abs(amount)
        let transaction = AccountTransaction(
            kind: kind,
            amount: kind == .deposit ? magnitude : -magnitude,
            date: date,
            payee: payee,
            note: note,
            isPosted: isPosted,
            checkNumber: kind == .check ? checkNumber : nil
        )
        context.insert(transaction)
        transaction.account = account
        transaction.category = category
        return transaction
    }

    /// Moves money between two accounts as a linked pair: money out of `source`, into `destination`.
    @discardableResult
    static func addTransfer(
        amount: Decimal,
        from source: Account,
        to destination: Account,
        date: Date = .now,
        note: String = "",
        isPosted: Bool = false,
        in context: ModelContext
    ) -> (outgoing: AccountTransaction, incoming: AccountTransaction) {
        let magnitude = abs(amount)
        let outgoing = AccountTransaction(kind: .transfer, amount: -magnitude, date: date, note: note, isPosted: isPosted)
        let incoming = AccountTransaction(kind: .transfer, amount: magnitude, date: date, note: note, isPosted: isPosted)
        context.insert(outgoing)
        context.insert(incoming)
        outgoing.account = source
        incoming.account = destination
        outgoing.incomingHalf = incoming
        return (outgoing, incoming)
    }

    /// Deletes a transaction, and the other half too if it's a transfer.
    static func delete(_ transaction: AccountTransaction, in context: ModelContext) {
        if let counterpart = transaction.transferCounterpart {
            context.delete(counterpart)
        }
        context.delete(transaction)
    }

    /// Finds a category by name, ignoring case and surrounding spaces, or creates it.
    /// Returns nil for a blank name, meaning "no category".
    static func category(named name: String, in context: ModelContext) throws -> Category? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let existing = try context.fetch(FetchDescriptor<Category>())
        if let match = existing.first(where: { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            return match
        }
        let category = Category(name: trimmed)
        context.insert(category)
        return category
    }
}
