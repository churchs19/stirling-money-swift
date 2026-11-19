import Foundation

/// Recurring transactions the app hasn't added yet, and the summary as it will be once they have.
///
/// The app adds due recurring transactions when it runs, which on iPhone can be hours after they fall due (and on the
/// Mac only while it's open). So the summary lists the next occurrences (`upcoming`), and the widgets, complications
/// and Watch show `projected(on:)`: the balances, goals and budgets as of that day, with anything due counted. Once
/// the app adds the real transactions, it writes a summary that no longer lists them.
nonisolated extension WidgetSnapshot {
    /// One occurrence of a recurring transaction that the app hasn't added yet.
    struct UpcomingOccurrence: Codable, Equatable {
        /// The day it falls due (the start of that day).
        var date: Date
        /// The account it's added to.
        var accountID: String
        /// How much it changes `accountID`'s balance: negative when money leaves.
        var amount: Decimal
        /// For a transfer, the account the money goes to (its balance changes by `-amount`).
        var otherAccountID: String? = nil
        /// The category's name, for category budgets.
        var categoryName: String? = nil
        var isTransfer: Bool = false
    }

    /// The summary as it will be on `date`'s day: occurrences due by then are added to account balances (not posted
    /// balances: they arrive unposted), goals on those accounts, and budgets whose current period they fall in, then
    /// dropped from `upcoming`. Projecting again on the same day changes nothing.
    func projected(on date: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        let day = calendar.startOfDay(for: date)
        let due = upcoming.filter { calendar.startOfDay(for: $0.date) <= day }
        guard !due.isEmpty else { return self }

        func change(in accountID: String) -> Decimal {
            due.reduce(Decimal(0)) { sum, occurrence in
                var sum = sum
                if occurrence.accountID == accountID {
                    sum += occurrence.amount
                }
                if occurrence.otherAccountID == accountID {
                    sum -= occurrence.amount
                }
                return sum
            }
        }

        var result = self
        result.upcoming = upcoming.filter { calendar.startOfDay(for: $0.date) > day }
        result.accounts = accounts.map { account in
            var account = account
            account.balance += change(in: account.id)
            return account
        }
        result.goals = goals.map { goal in
            guard let accountID = goal.accountID else { return goal }
            var goal = goal
            goal.currentAmount += change(in: accountID)
            if let initialBalance = goal.initialBalance {
                goal.progress = GoalSummary.progress(current: goal.currentAmount, target: goal.targetAmount, initial: initialBalance)
            }
            return goal
        }
        result.budgets = budgets.map { budget in
            var budget = budget
            for occurrence in due where budget.counts(occurrence) {
                // Spending is positive; money out is a negative amount.
                budget.spent -= occurrence.amount
            }
            return budget
        }
        return result
    }

    /// The days in the next `days` days (after today) when something falls due, for widget timelines.
    func upcomingDays(after now: Date, within days: Int = 45, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let last = calendar.date(byAdding: .day, value: days, to: today) ?? today
        let dates = upcoming.map { calendar.startOfDay(for: $0.date) }.filter { $0 > today && $0 <= last }
        return Array(Set(dates)).sorted()
    }
}

nonisolated extension WidgetSnapshot.BudgetSummary {
    /// Whether an occurrence counts toward this budget, by the same rule as `Budget.spent`: never transfers; for a
    /// category budget, that category's transactions (so refunds reduce spending); for an all-spending budget, money
    /// going out only. And only in the budget's current period.
    func counts(_ occurrence: WidgetSnapshot.UpcomingOccurrence) -> Bool {
        guard !occurrence.isTransfer, occurrence.date >= periodStart, occurrence.date < periodEnd else { return false }
        if let categoryName {
            return occurrence.categoryName == categoryName
        }
        return occurrence.amount < 0
    }
}

nonisolated extension WidgetSnapshot.GoalSummary {
    /// Fraction of the way from the starting balance to the target, from 0 to 1. `Goal.progress` uses this too.
    static func progress(current: Decimal, target: Decimal, initial: Decimal) -> Double {
        let span = target - initial
        guard span > 0 else { return current >= target ? 1 : 0 }
        let fraction = NSDecimalNumber(decimal: (current - initial) / span).doubleValue
        return min(max(fraction, 0), 1)
    }
}
