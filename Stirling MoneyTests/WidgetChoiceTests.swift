import Foundation
import Testing
@testable import Stirling_Money

/// Which goal, budget or account a widget or complication shows (`Shared/WidgetChoice.swift`).
struct WidgetChoiceTests {
    private let goals = WidgetSnapshot.sample.goals + [
        WidgetSnapshot.GoalSummary(
            id: "car", name: "New Car", accountName: "Savings", currentAmount: 100,
            targetAmount: 1000, progress: 0.1, targetDate: day(2027, 6, 1)
        ),
    ]
    private let budgets = WidgetSnapshot.sample.budgets

    @Test func noSummaryYet() {
        #expect(WidgetChoice<WidgetSnapshot.GoalSummary>.choose(id: nil, from: nil) == .noSummary)
        #expect(WidgetChoice<WidgetSnapshot.BudgetSummary>.choose(id: "food", from: nil) == .noSummary)
    }

    @Test func noneChosenShowsTheFirst() {
        #expect(WidgetChoice.choose(id: nil, from: goals) == .item(goals[0]))
        #expect(WidgetChoice.choose(id: nil, from: budgets) == .item(budgets[0]))
    }

    @Test func noneChosenAndNoneExist() {
        #expect(WidgetChoice<WidgetSnapshot.GoalSummary>.choose(id: nil, from: []) == .noneExist)
        #expect(WidgetChoice<WidgetSnapshot.BudgetSummary>.choose(id: nil, from: []) == .noneExist)
    }

    @Test func chosenOneIsShownWhereverItIs() {
        #expect(WidgetChoice.choose(id: "car", from: goals) == .item(goals[1]))
        #expect(WidgetChoice.choose(id: "fun", from: budgets) == .item(budgets[1]))
    }

    @Test func chosenOneThatIsGoneIsMissingNotTheFirst() {
        #expect(WidgetChoice.choose(id: "deleted", from: goals) == .missing)
        // Even when nothing is left: the widget should ask to be edited, not say "Add a budget".
        #expect(WidgetChoice<WidgetSnapshot.BudgetSummary>.choose(id: "food", from: []) == .missing)
    }

    @Test func itemIsOnlySetForAnItem() {
        #expect(WidgetChoice.choose(id: nil, from: goals).item == goals[0])
        #expect(WidgetChoice.choose(id: "deleted", from: goals).item == nil)
        #expect(WidgetChoice<WidgetSnapshot.GoalSummary>.choose(id: nil, from: nil).item == nil)
    }

    @Test func balanceWithNoAccountChosenShowsTheTotal() {
        let sample = WidgetSnapshot.sample
        #expect(BalanceChoice.choose(accountID: nil, in: sample) == .total)
        // Even with no accounts at all: the total is $0.
        let empty = WidgetSnapshot(accounts: [], goals: [], updatedAt: .now)
        #expect(BalanceChoice.choose(accountID: nil, in: empty) == .total)
    }

    @Test func balanceForAChosenAccount() {
        let sample = WidgetSnapshot.sample
        #expect(BalanceChoice.choose(accountID: "savings", in: sample) == .account(sample.accounts[1]))
        #expect(BalanceChoice.choose(accountID: "deleted", in: sample) == .missing)
        #expect(BalanceChoice.choose(accountID: nil, in: nil) == .noSummary)
        #expect(BalanceChoice.choose(accountID: "savings", in: nil) == .noSummary)
    }
}
