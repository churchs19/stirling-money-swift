import Foundation
import SwiftData

/// A transaction that repeats on a schedule, such as rent, pay or a monthly transfer to savings.
///
/// `RecurringScheduler` adds each occurrence as an ordinary, unposted `AccountTransaction` (through `Ledger`) on
/// `nextDate`, then moves `nextDate` on. Editing a rule changes future occurrences only; the transactions it already
/// added are ordinary transactions and stay when the rule is deleted.
@Model
final class RecurringTransaction {
    /// Its identity across devices (the CloudKit record name). Kept on deletion so the history tombstone says what
    /// was deleted.
    @Attribute(.preserveValueOnDeletion)
    var syncID: String = UUID().uuidString
    /// The book it belongs to. Set when it's created; see `Books`.
    var book: Book?

    var kindRawValue: String = TransactionKind.withdrawal.rawValue
    /// A positive amount; the kind decides the sign, as in `Ledger`.
    var amount: Decimal = 0
    var payee: String = ""
    var note: String = ""
    var createdAt: Date = Date.now

    var frequencyRawValue: String = RecurrenceFrequency.monthly.rawValue
    /// Every N weeks, months or years.
    var interval: Int = 1
    /// The first occurrence; its weekday, day of month or date sets the pattern.
    var startDate: Date = Date.now
    /// For twice a month: the other day of the month.
    var secondDay: Int = 15
    /// No occurrences after this day, if set.
    var endDate: Date?
    /// How many occurrences are left, if the rule stops after a number of times.
    var remainingCount: Int?
    /// The next occurrence to add. It only moves forward.
    var nextDate: Date = Date.now

    /// The account the transaction is added to (the money leaves it for a transfer).
    var account: Account?
    /// For a transfer: where the money goes. nil if that account was deleted.
    var otherAccount: Account?
    var category: Category?

    /// The transactions this rule has added. Deleting the rule keeps them.
    @Relationship(deleteRule: .nullify, inverse: \AccountTransaction.recurrence)
    var transactions: [AccountTransaction]? = []

    init(
        kind: TransactionKind,
        amount: Decimal,
        payee: String = "",
        note: String = "",
        frequency: RecurrenceFrequency,
        interval: Int = 1,
        startDate: Date,
        secondDay: Int = 15,
        endDate: Date? = nil,
        remainingCount: Int? = nil,
        calendar: Calendar = .current
    ) {
        kindRawValue = kind.rawValue
        self.amount = abs(amount)
        self.payee = payee
        self.note = note
        frequencyRawValue = frequency.rawValue
        self.interval = max(interval, 1)
        self.startDate = calendar.startOfDay(for: startDate)
        self.secondDay = secondDay
        self.endDate = endDate.map { calendar.startOfDay(for: $0) }
        self.remainingCount = remainingCount
        nextDate = calendar.startOfDay(for: startDate)
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRawValue) ?? .withdrawal }
        set { kindRawValue = newValue.rawValue }
    }

    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRawValue) ?? .monthly }
        set { frequencyRawValue = newValue.rawValue }
    }

    var schedule: RecurrenceSchedule {
        RecurrenceSchedule(frequency: frequency, interval: interval, start: startDate, secondDay: secondDay)
    }

    /// Whether the rule has no more occurrences: its count is used up, or the next one is past the end date.
    func hasEnded(calendar: Calendar = .current) -> Bool {
        if let remainingCount, remainingCount <= 0 {
            return true
        }
        if let endDate {
            return calendar.startOfDay(for: nextDate) > calendar.startOfDay(for: endDate)
        }
        return false
    }

    /// The occurrences still to add, from `nextDate` through `last`'s day, within the end date and count.
    func upcomingDates(through last: Date, limit: Int = 100, calendar: Calendar = .current) -> [Date] {
        guard problem == nil else { return [] }
        var lastDay = calendar.startOfDay(for: last)
        if let endDate {
            lastDay = min(lastDay, calendar.startOfDay(for: endDate))
        }
        let cap = min(limit, remainingCount ?? limit)
        var dates: [Date] = []
        var current = calendar.startOfDay(for: nextDate)
        while current <= lastDay, dates.count < cap {
            dates.append(current)
            current = schedule.next(after: current, calendar: calendar)
        }
        return dates
    }

    /// Why the rule can't add its next occurrence, if it can't: its account is gone, or a transfer's other account is.
    var problem: String? {
        if account == nil {
            return String(localized: "The account was deleted.")
        }
        if kind == .transfer, otherAccount == nil {
            return String(localized: "The account to transfer to was deleted. Choose another.")
        }
        return nil
    }

    /// The payee for display. Transfers name the other account, as transfer transactions do.
    var displayPayee: String {
        displayPayee(in: account)
    }

    /// The payee as seen from `viewer`: an incoming transfer reads "Transfer from …" in the account it goes to.
    func displayPayee(in viewer: Account?) -> String {
        guard kind == .transfer else { return payee }
        if let viewer, viewer === otherAccount {
            return String(localized: "Transfer from \(account?.name ?? "")")
        }
        guard let otherAccount else { return String(localized: "Transfer") }
        return String(localized: "Transfer to \(otherAccount.name)")
    }

    /// The amount each occurrence adds to `viewer`'s balance: negative when money leaves it.
    func signedAmount(in viewer: Account?) -> Decimal {
        switch kind {
        case .deposit: amount
        case .withdrawal, .check: -amount
        case .transfer: viewer != nil && viewer === otherAccount ? amount : -amount
        }
    }
}
