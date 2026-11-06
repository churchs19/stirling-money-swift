import Foundation

/// Where a budget stands on a given day, for its card.
struct BudgetSummary {
    enum State: Equatable {
        /// The period being tracked. If the budget's end date falls inside the period,
        /// the period is cut short at the end date.
        case active(DateInterval)
        case notStarted
        case ended
    }

    let state: State
    let amount: Decimal
    /// Spending in the current period, as a positive amount. Zero unless active.
    let spent: Decimal

    /// Money left in the period; negative when over budget.
    var remaining: Decimal {
        amount - spent
    }

    var isOverBudget: Bool {
        spent > amount
    }

    /// Fraction of the budget spent, from 0 to 1.
    var progress: Double {
        guard amount > 0 else { return spent > 0 ? 1 : 0 }
        let fraction = NSDecimalNumber(decimal: spent / amount).doubleValue
        return min(max(fraction, 0), 1)
    }
}

extension Budget {
    /// The budget's current period and spending on `date`.
    /// `allTransactions` is only read for an all-spending budget; a category budget uses its category's.
    func summary(
        on date: Date = .now,
        allTransactions: [AccountTransaction],
        calendar: Calendar = .current
    ) -> BudgetSummary {
        guard date >= calendar.startOfDay(for: startDate) else {
            return BudgetSummary(state: .notStarted, amount: amount, spent: 0)
        }
        guard isActive(on: date, calendar: calendar),
              var period = interval(containing: date, calendar: calendar)
        else {
            return BudgetSummary(state: .ended, amount: amount, spent: 0)
        }

        if let endDate,
           let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)),
           endExclusive < period.end
        {
            period = DateInterval(start: period.start, end: endExclusive)
        }

        let candidates = if let category { category.transactions ?? [] } else { allTransactions }
        return BudgetSummary(state: .active(period), amount: amount, spent: spent(during: period, from: candidates))
    }
}

extension DateInterval {
    /// The interval's days as text, e.g. "Nov 1 – 30". The end is exclusive, so the last day shown is the day before.
    func formattedDays(calendar: Calendar = .current) -> String {
        let lastDay = calendar.date(byAdding: .day, value: -1, to: end) ?? end
        guard lastDay > start else { return start.formatted(.dateTime.month(.abbreviated).day()) }
        return (start ..< lastDay).formatted(.interval.month(.abbreviated).day().year())
    }
}
