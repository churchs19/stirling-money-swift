import Foundation
import SwiftData

/// A savings target for one account, measured by that account's balance.
@Model
final class Goal {
    /// Its identity across devices (the CloudKit record name). Kept on deletion so the history tombstone says what
    /// was deleted.
    @Attribute(.preserveValueOnDeletion)
    var syncID: String = UUID().uuidString
    /// The book it belongs to. Set when it's created; see `Books`.
    var book: Book?
    /// The CloudKit record's system fields (change tag and so on) from the last sync, so the next save is checked
    /// against the server's copy. nil until first synced. Kept on deletion: the tombstone's copy names the record.
    @Attribute(.preserveValueOnDeletion)
    var ckSystemFields: Data?
    /// The record's values as of the last sync, for merging a conflict (`RecordMerger`).
    var ckSyncedValues: Data?

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
        // Shared with the widgets' projection, so the two can't disagree.
        WidgetSnapshot.GoalSummary.progress(current: currentAmount, target: targetAmount, initial: initialBalance)
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
