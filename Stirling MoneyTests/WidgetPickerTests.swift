import Foundation
import Testing
@testable import Stirling_Money

/// The account, goal and budget pickers shown when editing a widget (`Shared/WidgetIntents.swift`), and loading the
/// summary they read.
struct WidgetPickerTests {
    private let sample = WidgetSnapshot.sample

    @Test func pickersListEveryItemInTheSummary() async throws {
        let accounts = try await AccountQuery(summary: { sample }).suggestedEntities()
        #expect(accounts.map(\.id) == sample.accounts.map(\.id))
        #expect(accounts.map(\.name) == sample.accounts.map(\.name))

        let goals = try await GoalQuery(summary: { sample }).suggestedEntities()
        #expect(goals.map(\.id) == sample.goals.map(\.id))

        let budgets = try await BudgetQuery(summary: { sample }).suggestedEntities()
        #expect(budgets.map(\.id) == sample.budgets.map(\.id))
        #expect(budgets.map(\.name) == ["Food", "Fun"])
    }

    @Test func pickersAreEmptyBeforeTheAppWritesASummary() async throws {
        #expect(try await AccountQuery(summary: { nil }).suggestedEntities().isEmpty)
        #expect(try await GoalQuery(summary: { nil }).suggestedEntities().isEmpty)
        #expect(try await BudgetQuery(summary: { nil }).suggestedEntities().isEmpty)
    }

    @Test func lookingUpChosenItemsSkipsOnesThatAreGone() async throws {
        let accounts = AccountQuery(summary: { sample })
        #expect(try await accounts.entities(for: ["savings"]).map(\.name) == ["Savings"])
        // A widget configured for a deleted account gets nothing back for it, so it can say so.
        #expect(try await accounts.entities(for: ["deleted"]).isEmpty)
        #expect(try await accounts.entities(for: ["deleted", "checking"]).map(\.id) == ["checking"])
        #expect(try await accounts.entities(for: []).isEmpty)

        let budgets = BudgetQuery(summary: { sample })
        #expect(try await budgets.entities(for: ["fun", "food"]).count == 2)
        #expect(try await GoalQuery(summary: { sample }).entities(for: ["fund"]).map(\.name) == ["Emergency Fund"])
    }

    @Test func loadReadsASavedSummary() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try JSONEncoder().encode(sample).write(to: file)

        let loaded = try #require(WidgetSnapshot.load(from: file))
        #expect(loaded == sample)
    }

    @Test func loadGivesNilForAMissingOrUnreadableFile() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(WidgetSnapshot.load(from: file) == nil)
        #expect(WidgetSnapshot.load(from: nil) == nil)

        try Data("not a summary".utf8).write(to: file)
        #expect(WidgetSnapshot.load(from: file) == nil)
    }

    @Test func totalAddsEveryAccountIncludingNegativeBalances() {
        var snapshot = sample
        #expect(snapshot.total == 9750.75)
        snapshot.accounts.append(.init(id: "card", name: "Card", balance: -750.75, postedBalance: 0))
        #expect(snapshot.total == 9000)
        snapshot.accounts = []
        #expect(snapshot.total == 0)
    }
}
