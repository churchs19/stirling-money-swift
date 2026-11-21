import Foundation
import SwiftData

@Model
final class Budget {
    /// Its identity across devices (the CloudKit record name). Kept on deletion so the history tombstone says what
    /// was deleted.
    @Attribute(.preserveValueOnDeletion)
    var syncID: String = UUID().uuidString
    /// The book it belongs to. Set when it's created; see `Books`.
    var book: Book?
    /// The CloudKit record's system fields (change tag and so on) from the last sync, so the next save is checked
    /// against the server's copy. nil until first synced.
    var ckSystemFields: Data?

    var name: String = ""
    /// The spending limit per period, as a positive amount.
    var amount: Decimal = 0
    var periodRawValue: String = BudgetPeriod.monthly.rawValue
    var startDate: Date = Date.now
    /// Required for custom periods. For recurring periods, the budget stops after this date.
    var endDate: Date?
    /// nil means the budget covers all spending.
    var category: Category?

    init(
        name: String,
        amount: Decimal,
        period: BudgetPeriod = .monthly,
        startDate: Date = .now,
        endDate: Date? = nil
    ) {
        self.name = name
        self.amount = amount
        periodRawValue = period.rawValue
        self.startDate = startDate
        self.endDate = endDate
    }

    var period: BudgetPeriod {
        get { BudgetPeriod(rawValue: periodRawValue) ?? .monthly }
        set { periodRawValue = newValue.rawValue }
    }

    func interval(containing date: Date = .now, offset: Int = 0, calendar: Calendar = .current) -> DateInterval? {
        period.interval(start: startDate, end: endDate, containing: date, offset: offset, calendar: calendar)
    }

    /// Whether the budget applies on `date`: on or after the start, and not past the end date.
    func isActive(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        if date < calendar.startOfDay(for: startDate) {
            return false
        }
        if let endDate,
           let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)),
           date >= endExclusive
        {
            return false
        }
        return true
    }

    /// How much was spent during `interval`, as a positive amount. Transfers never count.
    ///
    /// - Category budget: the net of that category's transactions, so refunds reduce spending.
    /// - All-spending budget: money going out only; income isn't negative spending.
    ///
    /// `candidates` must include every transaction that might count. For a category budget,
    /// `category.transactions` is enough; for an all-spending budget, pass all transactions.
    func spent(during interval: DateInterval, from candidates: some Sequence<AccountTransaction>) -> Decimal {
        let budgetCategoryID = category?.persistentModelID
        let total = candidates
            .filter { transaction in
                guard transaction.kind != .transfer,
                      transaction.date >= interval.start,
                      transaction.date < interval.end
                else { return false }
                if let budgetCategoryID {
                    return transaction.category?.persistentModelID == budgetCategoryID
                }
                return transaction.amount < 0
            }
            .reduce(Decimal(0)) { $0 + $1.amount }
        return -total
    }
}
