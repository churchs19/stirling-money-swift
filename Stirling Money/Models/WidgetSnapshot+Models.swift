import Foundation
import SwiftData
import SwiftUI

extension WidgetSnapshot {
    /// A snapshot of the given accounts, goals and budgets, each sorted by name.
    /// `transactions` is only read for all-spending budgets. Budgets outside an active period are left out.
    init(
        accounts: [Account],
        goals: [Goal],
        budgets: [Budget] = [],
        transactions: [AccountTransaction] = [],
        recurring: [RecurringTransaction] = [],
        accentColor: Color.Resolved? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        self.accounts = AccountSort.name.sorted(accounts).map { account in
            var summary = AccountSummary(
                id: Self.widgetID(for: account), name: account.name,
                balance: account.balance, postedBalance: account.postedBalance
            )
            // The widget has the font but not the glyph table, so it gets the character itself.
            if let iconName = account.iconName {
                if let glyph = PaymentFont.glyph(forIconName: iconName) {
                    summary.iconGlyph = glyph.character
                } else {
                    summary.iconSymbol = iconName
                }
            }
            return summary
        }
        self.goals = goals
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map {
                GoalSummary(
                    id: Self.widgetID(for: $0),
                    name: $0.name,
                    accountName: $0.account?.name ?? "",
                    currentAmount: $0.currentAmount,
                    targetAmount: $0.targetAmount,
                    progress: $0.progress,
                    targetDate: $0.targetDate,
                    accountID: $0.account.map(Self.widgetID(for:)),
                    initialBalance: $0.initialBalance
                )
            }
        self.budgets = budgets
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .compactMap { budget in
                let summary = budget.summary(on: now, allTransactions: transactions, calendar: calendar)
                guard case let .active(period) = summary.state else { return nil }
                return BudgetSummary(
                    id: Self.widgetID(for: budget),
                    name: budget.name,
                    categoryName: budget.category?.name,
                    amount: summary.amount,
                    spent: summary.spent,
                    periodStart: period.start,
                    periodEnd: period.end,
                    periodTitle: budget.period.title
                )
            }
        // Occurrences in the next 45 days that haven't been added yet, for `projected(on:)`.
        let lookAhead = calendar.date(byAdding: .day, value: Self.lookAheadDays, to: calendar.startOfDay(for: now)) ?? now
        upcoming = recurring.flatMap { rule -> [UpcomingOccurrence] in
            guard let account = rule.account else { return [] }
            let accountID = Self.widgetID(for: account)
            let otherID = rule.kind == .transfer ? rule.otherAccount.map(Self.widgetID(for:)) : nil
            return rule.upcomingDates(through: lookAhead, calendar: calendar).map { date in
                UpcomingOccurrence(
                    date: date,
                    accountID: accountID,
                    amount: rule.signedAmount(in: account),
                    otherAccountID: otherID,
                    categoryName: rule.kind == .transfer ? nil : rule.category?.name,
                    isTransfer: rule.kind == .transfer
                )
            }
        }
        .sorted { $0.date < $1.date }
        self.accentColor = accentColor
        updatedAt = now
    }

    /// How far ahead `upcoming` lists recurring transactions.
    static let lookAheadDays = 45

    /// A stable string for a saved model, so a widget configured for an account keeps
    /// showing it after renames. Built from SwiftData's persistent identifier.
    static func widgetID(for model: some PersistentModel) -> String {
        // Sorted keys: otherwise the encoded key order varies between calls, and so would the ID.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(model.persistentModelID) else { return "" }
        return data.base64EncodedString()
    }
}
