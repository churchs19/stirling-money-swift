import Foundation
import SwiftData

/// Adds recurring transactions when they fall due.
///
/// Each occurrence becomes an ordinary, unposted transaction, added through `Ledger` (so signs and transfer pairs are
/// right) and linked to its rule. The rule's `nextDate` moves on in the same save, so running again adds nothing new.
/// Occurrences that came due while the app didn't run are all added, each on its own date.
enum RecurringScheduler {
    /// The most occurrences one rule adds in one run, so a rule with a start far in the past can't add thousands at
    /// once. The rest are added on the next run.
    static let catchUpLimit = 400

    /// Adds every occurrence due on or before `now`'s day and saves. Returns how many occurrences were added.
    @discardableResult
    static func addDue(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws -> Int {
        let today = calendar.startOfDay(for: now)
        var added = 0
        for rule in try context.fetch(FetchDescriptor<RecurringTransaction>()) where rule.problem == nil {
            var count = 0
            while count < catchUpLimit, !rule.hasEnded(calendar: calendar), calendar.startOfDay(for: rule.nextDate) <= today {
                addOccurrence(of: rule, on: rule.nextDate, occurrence: rule.nextDate, in: context, calendar: calendar)
                advance(rule, calendar: calendar)
                count += 1
            }
            added += count
        }
        if added > 0 {
            try context.save()
        }
        return added
    }

    /// Adds the next occurrence now, dated today, and moves the rule on past it. Returns the transaction added to the
    /// rule's account, or nil if the rule has ended or can't add one.
    @discardableResult
    static func addNow(
        _ rule: RecurringTransaction,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AccountTransaction? {
        guard rule.problem == nil, !rule.hasEnded(calendar: calendar) else { return nil }
        // Named for the occurrence it stands in for, so a device adding it on its due date writes the same record.
        let transaction = addOccurrence(
            of: rule, on: calendar.startOfDay(for: now), occurrence: rule.nextDate, in: context, calendar: calendar
        )
        advance(rule, calendar: calendar)
        return transaction
    }

    /// Skips the next occurrence without adding it. It counts toward an "after N times" end.
    static func skipNext(_ rule: RecurringTransaction, calendar: Calendar = .current) {
        guard !rule.hasEnded(calendar: calendar) else { return }
        advance(rule, calendar: calendar)
    }

    /// The earliest day a rule next falls due, for scheduling the next background run. nil when none will.
    static func nextDueDate(in context: ModelContext, calendar: Calendar = .current) throws -> Date? {
        try context.fetch(FetchDescriptor<RecurringTransaction>())
            .filter { $0.problem == nil && !$0.hasEnded(calendar: calendar) }
            .map(\.nextDate)
            .min()
    }

    // MARK: Adding one

    /// The `syncID` of a rule's occurrence that falls due on `date`: `"<rule syncID>:<yyyy-MM-dd>"`. Every device
    /// adding that occurrence gives it this name, so CloudKit keeps one record: no duplicates.
    static func occurrenceSyncID(of rule: RecurringTransaction, on date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let text = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        return "\(rule.syncID):\(text)"
    }

    /// Adds the occurrence due on `occurrence`, dated `date`, and links it to the rule. Returns the transaction in the
    /// rule's account.
    @discardableResult
    private static func addOccurrence(
        of rule: RecurringTransaction,
        on date: Date,
        occurrence: Date,
        in context: ModelContext,
        calendar: Calendar
    ) -> AccountTransaction? {
        guard let account = rule.account else { return nil }
        let syncID = occurrenceSyncID(of: rule, on: occurrence, calendar: calendar)
        switch rule.kind {
        case .transfer:
            guard let destination = rule.otherAccount else { return nil }
            let pair = Ledger.addTransfer(
                amount: rule.amount, from: account, to: destination, date: date, note: rule.note, pairID: syncID, in: context
            )
            // Both halves, so either one opens the rule.
            pair.outgoing.recurrence = rule
            pair.incoming.recurrence = rule
            return pair.outgoing
        case .withdrawal, .deposit, .check:
            let transaction = Ledger.addTransaction(
                rule.kind,
                amount: rule.amount,
                to: account,
                date: date,
                payee: rule.payee,
                note: rule.note,
                checkNumber: rule.kind == .check ? account.nextCheckNumber : nil,
                category: rule.category,
                syncID: syncID,
                in: context
            )
            transaction.recurrence = rule
            return transaction
        }
    }

    /// Moves the rule to its next occurrence and uses up one of a counted end.
    private static func advance(_ rule: RecurringTransaction, calendar: Calendar) {
        rule.nextDate = rule.schedule.next(after: rule.nextDate, calendar: calendar)
        if let remaining = rule.remainingCount {
            rule.remainingCount = max(remaining - 1, 0)
        }
    }
}
