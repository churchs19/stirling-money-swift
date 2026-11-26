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
        syncID: String? = nil,
        in context: ModelContext
    ) -> AccountTransaction {
        precondition(kind != .transfer, "Use Ledger.addTransfer for transfers")
        let transaction = AccountTransaction(
            kind: kind,
            amount: signedAmount(amount, for: kind),
            date: date,
            payee: payee,
            note: note,
            isPosted: isPosted,
            checkNumber: kind == .check ? checkNumber : nil
        )
        if let syncID {
            transaction.syncID = syncID
        }
        context.insert(transaction)
        transaction.book = account.book
        transaction.account = account
        transaction.category = category
        return transaction
    }

    /// Moves money between two accounts as a linked pair: money out of `source`, into `destination`.
    ///
    /// The halves' `syncID`s are `"<pairID>:out"` and `"<pairID>:in"`, so each half can name the other.
    @discardableResult
    static func addTransfer(
        amount: Decimal,
        from source: Account,
        to destination: Account,
        date: Date = .now,
        note: String = "",
        isPosted: Bool = false,
        pairID: String = UUID().uuidString,
        in context: ModelContext
    ) -> (outgoing: AccountTransaction, incoming: AccountTransaction) {
        let magnitude = abs(amount)
        let outgoing = AccountTransaction(kind: .transfer, amount: -magnitude, date: date, note: note, isPosted: isPosted)
        let incoming = AccountTransaction(kind: .transfer, amount: magnitude, date: date, note: note, isPosted: isPosted)
        outgoing.syncID = pairID + outgoingSuffix
        incoming.syncID = pairID + incomingSuffix
        context.insert(outgoing)
        context.insert(incoming)
        outgoing.book = source.book
        incoming.book = destination.book
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

    /// Finds a category in `book` by name, ignoring case and surrounding spaces, or creates it there.
    /// Returns nil for a blank name, meaning "no category".
    static func category(named name: String, book: Book? = nil, in context: ModelContext) throws -> Category? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let match = try existingCategory(named: trimmed, book: book, in: context) {
            return match
        }
        let category = Category(name: trimmed)
        context.insert(category)
        category.book = book
        return category
    }

    /// The category in `book` with this name, ignoring case and surrounding spaces, other than `excluded`.
    /// Used to stop a rename from creating two categories with the same name. Other books may use the same names.
    static func existingCategory(
        named name: String,
        excluding excluded: Category? = nil,
        book: Book? = nil,
        in context: ModelContext
    ) throws -> Category? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let bookID = book?.persistentModelID
        return try context.fetch(FetchDescriptor<Category>()).first {
            $0 !== excluded && $0.book?.persistentModelID == bookID
                && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }
    }

    static let outgoingSuffix = ":out"
    static let incomingSuffix = ":in"

    /// The `syncID` for the other half of the transfer half with `syncID`: `:out` and `:in` swapped, or for a half
    /// made before transfers were named in pairs, its own ID with a suffix.
    static func counterpartSyncID(of syncID: String, isIncoming: Bool) -> String {
        let (own, other) = isIncoming ? (incomingSuffix, outgoingSuffix) : (outgoingSuffix, incomingSuffix)
        if syncID.hasSuffix(own) {
            return String(syncID.dropLast(own.count)) + other
        }
        return syncID + other
    }

    /// Deposits are positive; everything else takes money out of the account.
    static func signedAmount(_ amount: Decimal, for kind: TransactionKind) -> Decimal {
        kind == .deposit ? abs(amount) : -abs(amount)
    }
}

// MARK: - Saving the transaction form

extension Ledger {
    /// Saves the transaction form: adds a new entry to `account`, or updates `existing`.
    /// Returns the entry shown in `account`'s register, or nil if the draft isn't valid.
    ///
    /// Changing a transfer into another kind, or the other way round, changes how many entries
    /// there are, so the old entry (and its other half) is deleted and a new one is created.
    @discardableResult
    static func save(
        _ draft: TransactionDraft,
        in account: Account,
        editing existing: AccountTransaction? = nil,
        context: ModelContext
    ) -> AccountTransaction? {
        guard draft.isValid, let amount = draft.amount else { return nil }
        var draft = draft
        draft.category = CategoryMerger.survivor(of: draft.category)

        var existing = existing
        if let current = existing, (current.kind == .transfer) != (draft.kind == .transfer) {
            delete(current, in: context)
            existing = nil
        }

        if draft.kind == .transfer {
            guard let other = draft.otherAccount, other !== account else { return nil }
            if let existing {
                updateTransfer(existing, amount: amount, otherAccount: other, from: draft, in: context)
                return existing
            }
            if draft.isIncomingTransfer {
                return addTransfer(
                    amount: amount, from: other, to: account, date: draft.date,
                    note: draft.trimmedNote, isPosted: draft.isPosted, in: context
                ).incoming
            }
            return addTransfer(
                amount: amount, from: account, to: other, date: draft.date,
                note: draft.trimmedNote, isPosted: draft.isPosted, in: context
            ).outgoing
        }

        guard let existing else {
            return addTransaction(
                draft.kind, amount: amount, to: account, date: draft.date, payee: draft.trimmedPayee,
                note: draft.trimmedNote, isPosted: draft.isPosted, checkNumber: draft.checkNumber,
                category: draft.category, in: context
            )
        }
        existing.kind = draft.kind
        existing.amount = signedAmount(amount, for: draft.kind)
        existing.date = draft.date
        existing.payee = draft.trimmedPayee
        existing.note = draft.trimmedNote
        existing.isPosted = draft.isPosted
        existing.checkNumber = draft.kind == .check ? draft.checkNumber : nil
        existing.category = draft.category
        return existing
    }

    /// Updates one half of a transfer and keeps the other half in step. Posted status stays
    /// separate, since each bank clears its side on its own schedule.
    /// If the other half was lost when its account was deleted, a new one is created.
    private static func updateTransfer(
        _ half: AccountTransaction,
        amount: Decimal,
        otherAccount: Account,
        from draft: TransactionDraft,
        in context: ModelContext
    ) {
        let isIncoming = half.amount > 0
        half.amount = isIncoming ? amount : -amount
        half.date = draft.date
        half.note = draft.trimmedNote
        half.isPosted = draft.isPosted
        half.payee = ""
        half.checkNumber = nil
        half.category = nil

        if let counterpart = half.transferCounterpart {
            counterpart.amount = -half.amount
            counterpart.date = draft.date
            counterpart.note = draft.trimmedNote
            counterpart.account = otherAccount
            return
        }

        let counterpart = AccountTransaction(
            kind: .transfer, amount: -half.amount, date: draft.date,
            note: draft.trimmedNote, isPosted: draft.isPosted
        )
        counterpart.syncID = counterpartSyncID(of: half.syncID, isIncoming: isIncoming)
        context.insert(counterpart)
        counterpart.book = otherAccount.book
        counterpart.account = otherAccount
        if isIncoming {
            counterpart.incomingHalf = half
        } else {
            half.incomingHalf = counterpart
        }
    }
}
