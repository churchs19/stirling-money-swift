import Foundation
import SwiftData

/// How a recurring transaction ends.
nonisolated enum RecurringEnd: String, CaseIterable, Identifiable {
    case never
    case onDate
    case afterCount

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .never: String(localized: "Never")
        case .onDate: String(localized: "On a Date")
        case .afterCount: String(localized: "After a Number of Times")
        }
    }
}

/// The recurring transaction form's fields, kept as typed text until saved, like `TransactionDraft`.
struct RecurringDraft {
    var kind: TransactionKind = .withdrawal
    /// Entered without a sign; the kind decides whether money goes in or out.
    var amountText = ""
    var payee = ""
    var note = ""
    var category: Category?
    /// The account the transaction is added to (the money leaves it for a transfer).
    var account: Account?
    /// For a transfer, where the money goes.
    var otherAccount: Account?

    var frequency: RecurrenceFrequency = .monthly
    var interval = 1
    var startDate: Date
    var secondDay = 15

    var end: RecurringEnd = .never
    var endDate: Date
    /// For an end after a number of times: how many (when editing, how many are left).
    var countText = ""

    /// A blank form for a new rule in `account`, starting today.
    init(account: Account?, now: Date = .now, calendar: Calendar = .current) {
        self.account = account
        startDate = calendar.startOfDay(for: now)
        endDate = calendar.date(byAdding: .year, value: 1, to: startDate) ?? startDate
    }

    /// "Make Recurring…": the transaction's details, repeating monthly from a month after it.
    init(from transaction: AccountTransaction, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: transaction.date)
        startDate = calendar.date(byAdding: .month, value: 1, to: day) ?? day
        endDate = calendar.date(byAdding: .year, value: 1, to: startDate) ?? startDate
        kind = transaction.kind
        amountText = abs(transaction.amount).formatted(.localCurrency)
        note = transaction.note
        if transaction.kind == .transfer {
            // The rule always moves money from its account, so start from the outgoing side.
            let otherSide = transaction.transferCounterpart?.account
            if transaction.amount < 0 {
                account = transaction.account
                otherAccount = otherSide
            } else {
                account = otherSide
                otherAccount = transaction.account
            }
        } else {
            account = transaction.account
            payee = transaction.payee
            category = transaction.category
        }
    }

    /// The form filled in from an existing rule.
    init(editing rule: RecurringTransaction, calendar: Calendar = .current) {
        kind = rule.kind
        amountText = rule.amount.formatted(.localCurrency)
        payee = rule.payee
        note = rule.note
        category = rule.category
        account = rule.account
        otherAccount = rule.otherAccount
        frequency = rule.frequency
        interval = rule.interval
        startDate = rule.startDate
        secondDay = rule.secondDay
        if let ruleEnd = rule.endDate {
            end = .onDate
            endDate = ruleEnd
        } else {
            endDate = calendar.date(byAdding: .year, value: 1, to: rule.startDate) ?? rule.startDate
        }
        if let remaining = rule.remainingCount {
            end = .afterCount
            countText = String(remaining)
        }
    }

    // MARK: Values

    var trimmedPayee: String {
        payee.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The amount as a positive number, or nil if it's blank, zero or not a number.
    var amount: Decimal? {
        Decimal(positiveUserInput: amountText)
    }

    var hasInvalidAmount: Bool {
        !amountText.trimmingCharacters(in: .whitespaces).isEmpty && amount == nil
    }

    /// The number of times, or nil when blank or not a whole number above zero.
    var count: Int? {
        guard let number = Int(countText.trimmingCharacters(in: .whitespaces)), number > 0 else { return nil }
        return number
    }

    var hasInvalidCount: Bool {
        end == .afterCount && !countText.trimmingCharacters(in: .whitespaces).isEmpty && count == nil
    }

    func schedule(calendar: Calendar = .current) -> RecurrenceSchedule {
        RecurrenceSchedule(
            frequency: frequency,
            interval: frequency == .twiceMonthly ? 1 : max(interval, 1),
            start: calendar.startOfDay(for: startDate),
            secondDay: secondDay
        )
    }

    /// Twice a month on the same day twice.
    func hasSameDayTwice(calendar: Calendar = .current) -> Bool {
        frequency == .twiceMonthly && calendar.component(.day, from: startDate) == secondDay
    }

    func endsBeforeStart(calendar: Calendar = .current) -> Bool {
        end == .onDate && calendar.startOfDay(for: endDate) < calendar.startOfDay(for: startDate)
    }

    var isValid: Bool {
        isValid(calendar: .current)
    }

    func isValid(calendar: Calendar) -> Bool {
        guard amount != nil, let account, (1 ... 99).contains(interval) else { return false }
        if kind == .transfer {
            guard let otherAccount, otherAccount !== account else { return false }
        } else if trimmedPayee.isEmpty {
            return false
        }
        if hasSameDayTwice(calendar: calendar) || endsBeforeStart(calendar: calendar) {
            return false
        }
        if end == .afterCount, count == nil {
            return false
        }
        return true
    }

    /// The next few occurrences from `now`, for the form's preview.
    func upcomingDates(_ count: Int = 3, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        let schedule = schedule(calendar: calendar)
        var dates: [Date] = []
        var current = schedule.next(onOrAfter: max(schedule.start, calendar.startOfDay(for: now)), calendar: calendar)
        let lastDay = end == .onDate ? calendar.startOfDay(for: endDate) : nil
        let limit = end == .afterCount ? min(count, self.count ?? count) : count
        while dates.count < limit {
            if let lastDay, current > lastDay {
                break
            }
            dates.append(current)
            current = schedule.next(after: current, calendar: calendar)
        }
        return dates
    }

    // MARK: Saving

    /// Creates a rule, or updates `rule`, and returns it; nil if the form isn't valid.
    ///
    /// Editing changes future occurrences only. When the schedule changes, the next occurrence is worked out again
    /// from today (or the new start, if later), so occurrences already added aren't added again.
    @discardableResult
    func save(
        in context: ModelContext,
        editing rule: RecurringTransaction? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> RecurringTransaction? {
        guard isValid(calendar: calendar), let amount, let account else { return nil }
        let schedule = schedule(calendar: calendar)

        let target: RecurringTransaction
        if let rule {
            target = rule
            if rule.schedule != schedule {
                rule.nextDate = schedule.next(onOrAfter: max(schedule.start, calendar.startOfDay(for: now)), calendar: calendar)
            }
        } else {
            target = RecurringTransaction(
                kind: kind, amount: amount, frequency: frequency, startDate: schedule.start, calendar: calendar
            )
            context.insert(target)
        }

        target.kind = kind
        target.amount = amount
        target.payee = kind == .transfer ? "" : trimmedPayee
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        target.frequency = frequency
        target.interval = schedule.interval
        target.startDate = schedule.start
        target.secondDay = secondDay
        target.endDate = end == .onDate ? calendar.startOfDay(for: endDate) : nil
        target.remainingCount = end == .afterCount ? count : nil
        target.account = account
        target.otherAccount = kind == .transfer ? otherAccount : nil
        target.category = kind == .transfer ? nil : category
        return target
    }
}
