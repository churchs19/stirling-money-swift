import Foundation
import SwiftData

/// A savings target for one account, measured by that account's balance.
@Model
final class Goal {
    var name: String = ""
    var targetAmount: Decimal = 0
    /// The account's balance when the goal was created; progress is measured from here.
    var initialBalance: Decimal = 0
    var startDate: Date = Date.now
    var targetDate: Date = Date.now

    var account: Account?

    /// Records the account's current balance as the starting point. Insert the goal, then set `account`.
    init(name: String, targetAmount: Decimal, targetDate: Date, initialBalance: Decimal, startDate: Date = .now) {
        self.name = name
        self.targetAmount = targetAmount
        self.targetDate = targetDate
        self.initialBalance = initialBalance
        self.startDate = startDate
    }

    var currentAmount: Decimal {
        account?.balance ?? 0
    }

    /// How much more is needed; zero once the goal is met.
    var amountRemaining: Decimal {
        max(targetAmount - currentAmount, 0)
    }

    /// Fraction of the way from the starting balance to the target, from 0 to 1.
    var progress: Double {
        let span = targetAmount - initialBalance
        guard span > 0 else { return currentAmount >= targetAmount ? 1 : 0 }
        let fraction = NSDecimalNumber(decimal: (currentAmount - initialBalance) / span).doubleValue
        return min(max(fraction, 0), 1)
    }

    /// Whole days until the target date; negative once it's overdue.
    func daysRemaining(from date: Date = .now, calendar: Calendar = .current) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: targetDate)
        ).day ?? 0
    }
}
