import Foundation
import SwiftData

/// The budget form's fields, kept as typed text until saved.
struct BudgetDraft {
    var name = ""
    var amountText = ""
    /// nil means all spending.
    var category: Category?
    var period: BudgetPeriod = .monthly
    var startDate: Date
    /// Recurring budgets can optionally stop; custom budgets always need an end date.
    var hasEndDate = false
    var endDate: Date

    /// A blank form: a monthly budget starting on the first of this month.
    init(now: Date = .now, calendar: Calendar = .current) {
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        startDate = monthStart
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        endDate = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? monthStart
    }

    init(editing budget: Budget, calendar: Calendar = .current) {
        self.init(now: budget.startDate, calendar: calendar)
        name = budget.name
        amountText = budget.amount.formatted(.localCurrency)
        category = budget.category
        period = budget.period
        startDate = budget.startDate
        if let budgetEnd = budget.endDate {
            hasEndDate = true
            endDate = budgetEnd
        }
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var amount: Decimal? {
        Decimal(positiveUserInput: amountText)
    }

    var hasInvalidAmount: Bool {
        !amountText.trimmingCharacters(in: .whitespaces).isEmpty && amount == nil
    }

    /// The end date that will be saved, if any.
    var effectiveEndDate: Date? {
        period == .custom || hasEndDate ? endDate : nil
    }

    func hasEndBeforeStart(calendar: Calendar = .current) -> Bool {
        guard let effectiveEndDate else { return false }
        return calendar.startOfDay(for: effectiveEndDate) < calendar.startOfDay(for: startDate)
    }

    var isValid: Bool {
        !trimmedName.isEmpty && amount != nil && !hasEndBeforeStart()
    }

    /// Creates a budget, or updates `existing`. Returns nil if the draft isn't valid.
    @discardableResult
    func save(editing existing: Budget? = nil, in context: ModelContext) -> Budget? {
        guard isValid, let amount else { return nil }
        let budget: Budget
        if let existing {
            budget = existing
            budget.name = trimmedName
            budget.amount = amount
            budget.period = period
            budget.startDate = startDate
            budget.endDate = effectiveEndDate
        } else {
            budget = Budget(name: trimmedName, amount: amount, period: period, startDate: startDate, endDate: effectiveEndDate)
            context.insert(budget)
        }
        budget.category = category
        return budget
    }
}
