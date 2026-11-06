import Foundation

/// Income and spending for one month. Transfers never count.
struct MonthTotal: Identifiable, Equatable {
    /// The first moment of the month.
    let month: Date
    /// Money coming in, as a positive amount.
    var income: Decimal = 0
    /// Money going out, as a positive amount.
    var expenses: Decimal = 0

    var net: Decimal {
        income - expenses
    }

    var id: Date {
        month
    }
}

/// One category's net spending in one month: spending less refunds, so it can be negative.
struct MonthAmount: Identifiable, Equatable {
    let month: Date
    let amount: Decimal

    var id: Date {
        month
    }
}

/// A slice of the spending-by-category chart.
struct CategorySlice: Identifiable, Equatable {
    /// The category's name; nil for transactions with no category.
    let categoryName: String?
    let amount: Decimal
    /// The chart color slot, which stays with the category whatever range is shown.
    /// nil for the "Other" slice.
    let colorSlot: Int?

    var isOther: Bool {
        colorSlot == nil
    }

    var id: String {
        if isOther {
            return "\u{0}other"
        }
        return categoryName ?? "\u{0}uncategorized"
    }
}

/// What a budget spent in one of its periods.
struct BudgetPeriodTotal: Identifiable, Equatable {
    let interval: DateInterval
    let spent: Decimal

    var id: Date {
        interval.start
    }
}

/// The calculations behind the Reports tab. Transfers are left out of every report:
/// moving money between your own accounts is neither income nor spending.
enum Reports {
    /// The start of each of the last `count` months, oldest first, ending with the month containing `date`.
    static func months(count: Int, endingAt date: Date, calendar: Calendar = .current) -> [Date] {
        let current = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        return (0 ..< max(count, 0)).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: current)
        }
    }

    /// From the start of the first of the last `count` months to the end of the month containing `date`.
    static func monthRange(count: Int, endingAt date: Date, calendar: Calendar = .current) -> DateInterval {
        let starts = months(count: count, endingAt: date, calendar: calendar)
        let start = starts.first ?? date
        let lastStart = starts.last ?? date
        let end = calendar.date(byAdding: .month, value: 1, to: lastStart) ?? lastStart
        return DateInterval(start: start, end: end)
    }

    // MARK: Net income

    /// Income and expenses for each of the last `months` months, oldest first.
    static func incomeAndExpenses(
        _ transactions: [AccountTransaction],
        months count: Int,
        endingAt date: Date = .now,
        calendar: Calendar = .current
    ) -> [MonthTotal] {
        var totals = months(count: count, endingAt: date, calendar: calendar).map { MonthTotal(month: $0) }
        let index = Dictionary(uniqueKeysWithValues: totals.enumerated().map { ($1.month, $0) })

        for transaction in transactions where transaction.kind != .transfer {
            guard let month = calendar.dateInterval(of: .month, for: transaction.date)?.start,
                  let position = index[month]
            else { continue }
            if transaction.amount > 0 {
                totals[position].income += transaction.amount
            } else {
                totals[position].expenses -= transaction.amount
            }
        }
        return totals
    }

    // MARK: Spending by category

    /// Net spending (spending less refunds) for each category, keyed by name; nil is uncategorized.
    private static func netSpendingByCategory(
        _ transactions: some Sequence<AccountTransaction>,
        in interval: DateInterval? = nil
    ) -> [String?: Decimal] {
        var totals: [String?: Decimal] = [:]
        for transaction in transactions where transaction.kind != .transfer {
            if let interval, !(transaction.date >= interval.start && transaction.date < interval.end) {
                continue
            }
            totals[transaction.category?.name, default: 0] -= transaction.amount
        }
        return totals
    }

    /// Spending in `interval` by category: up to `namedSlices` categories plus "Other", largest first.
    ///
    /// The named categories are the biggest over *all* of `transactions`, not just `interval`,
    /// and each keeps its color slot, so changing the range doesn't repaint the chart.
    /// Categories whose refunds outweigh their spending are left out.
    static func spendingByCategory(
        _ transactions: [AccountTransaction],
        in interval: DateInterval,
        namedSlices: Int = 7
    ) -> [CategorySlice] {
        let ranked = netSpendingByCategory(transactions)
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return (lhs.key ?? "").localizedStandardCompare(rhs.key ?? "") == .orderedAscending
            }
            .prefix(namedSlices)
            .map(\.key)
        let slots = Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($1, $0) })

        var named: [CategorySlice] = []
        var other: Decimal = 0
        for (name, amount) in netSpendingByCategory(transactions, in: interval) where amount > 0 {
            if let slot = slots[name] {
                named.append(CategorySlice(categoryName: name, amount: amount, colorSlot: slot))
            } else {
                other += amount
            }
        }
        named.sort { $0.amount != $1.amount ? $0.amount > $1.amount : ($0.colorSlot ?? 0) < ($1.colorSlot ?? 0) }
        if other > 0 {
            named.append(CategorySlice(categoryName: nil, amount: other, colorSlot: nil))
        }
        return named
    }

    // MARK: One category over time

    /// One category's net spending for each of the last `months` months, oldest first.
    static func spending(
        in category: Category,
        months count: Int,
        endingAt date: Date = .now,
        calendar: Calendar = .current
    ) -> [MonthAmount] {
        var totals: [Date: Decimal] = [:]
        for transaction in category.transactions ?? [] where transaction.kind != .transfer {
            guard let month = calendar.dateInterval(of: .month, for: transaction.date)?.start else { continue }
            totals[month, default: 0] -= transaction.amount
        }
        return months(count: count, endingAt: date, calendar: calendar).map {
            MonthAmount(month: $0, amount: totals[$0] ?? 0)
        }
    }

    // MARK: Budget history

    /// What a budget spent in each of its last `periods` periods, oldest first, up to the one containing
    /// `date` (or the last one, if the budget has ended). Periods before the budget started are left out.
    static func history(
        of budget: Budget,
        allTransactions: [AccountTransaction],
        periods: Int = 7,
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> [BudgetPeriodTotal] {
        let anchor = calendar.startOfDay(for: budget.startDate)
        guard date >= anchor else { return [] }

        var endExclusive: Date?
        if let endDate = budget.endDate {
            endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))
        }
        // For an ended budget, show the periods leading up to its end.
        var reference = date
        if let endExclusive, reference >= endExclusive {
            reference = endExclusive.addingTimeInterval(-1)
        }

        let candidates = if let category = budget.category {
            category.transactions ?? []
        } else {
            allTransactions
        }
        let count = budget.period == .custom ? 1 : periods

        return (0 ..< count).reversed().compactMap { back in
            guard var interval = budget.interval(containing: reference, offset: -back, calendar: calendar),
                  interval.start >= anchor
            else { return nil }
            if let endExclusive, endExclusive < interval.end, endExclusive > interval.start {
                interval = DateInterval(start: interval.start, end: endExclusive)
            }
            return BudgetPeriodTotal(interval: interval, spent: budget.spent(during: interval, from: candidates))
        }
    }
}

nonisolated extension Decimal {
    /// The amount as a Double, for plotting. Charts don't need Decimal's precision.
    var chartValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
