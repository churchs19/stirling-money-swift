import Foundation
import SwiftData

/// The goal form's fields, kept as typed text until saved.
struct GoalDraft {
    var name = ""
    var targetText = ""
    var account: Account?
    var targetDate: Date

    /// A blank form with a target a year from now.
    init(account: Account? = nil, now: Date = .now, calendar: Calendar = .current) {
        self.account = account
        targetDate = calendar.date(byAdding: .year, value: 1, to: now) ?? now
    }

    init(editing goal: Goal) {
        name = goal.name
        targetText = goal.targetAmount.formatted(.localCurrency)
        account = goal.account
        targetDate = goal.targetDate
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var target: Decimal? {
        Decimal(positiveUserInput: targetText)
    }

    var hasInvalidTarget: Bool {
        !targetText.trimmingCharacters(in: .whitespaces).isEmpty && target == nil
    }

    var isValid: Bool {
        !trimmedName.isEmpty && target != nil && account != nil
    }

    /// Creates a goal, or updates `existing`. Returns nil if the draft isn't valid.
    ///
    /// Progress is measured from the account's balance when the goal starts, so a new goal,
    /// or one moved to a different account, starts again from that account's balance today.
    @discardableResult
    func save(editing existing: Goal? = nil, in context: ModelContext, now: Date = .now) -> Goal? {
        guard isValid, let target, let account else { return nil }
        if let existing {
            existing.name = trimmedName
            existing.targetAmount = target
            existing.targetDate = targetDate
            if existing.account !== account {
                existing.initialBalance = account.balance
                existing.startDate = now
                existing.account = account
            }
            return existing
        }
        let goal = Goal(name: trimmedName, targetAmount: target, targetDate: targetDate, initialBalance: account.balance, startDate: now)
        context.insert(goal)
        goal.book = account.book
        goal.account = account
        return goal
    }
}
