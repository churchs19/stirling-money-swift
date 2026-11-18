import AppIntents
import WidgetKit

// Widget configuration, shared by the iPhone widgets and the Watch complications (both read the summary).
// `nonisolated` because the app target, which also compiles Shared/, defaults to the main actor.

/// An account a widget can show, read from the snapshot.
nonisolated struct AccountEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Account"
    }

    static let defaultQuery = AccountQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

nonisolated struct AccountQuery: EntityQuery {
    func entities(for identifiers: [AccountEntity.ID]) async throws -> [AccountEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AccountEntity] {
        (WidgetSnapshot.load()?.accounts ?? []).map { AccountEntity(id: $0.id, name: $0.name) }
    }
}

/// A goal a widget can show, read from the snapshot.
nonisolated struct GoalEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Goal"
    }

    static let defaultQuery = GoalQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

nonisolated struct GoalQuery: EntityQuery {
    func entities(for identifiers: [GoalEntity.ID]) async throws -> [GoalEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [GoalEntity] {
        (WidgetSnapshot.load()?.goals ?? []).map { GoalEntity(id: $0.id, name: $0.name) }
    }
}

/// A budget a widget can show, read from the snapshot (which only has budgets in an active period).
nonisolated struct BudgetEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Budget"
    }

    static let defaultQuery = BudgetQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

nonisolated struct BudgetQuery: EntityQuery {
    func entities(for identifiers: [BudgetEntity.ID]) async throws -> [BudgetEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BudgetEntity] {
        (WidgetSnapshot.load()?.budgets ?? []).map { BudgetEntity(id: $0.id, name: $0.name) }
    }
}

struct SelectAccountIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource {
        "Account"
    }

    static var description: IntentDescription {
        "Shows an account's balance, or the total of all accounts."
    }

    @Parameter(title: "Account", description: "Leave empty to show the total of all accounts.")
    var account: AccountEntity?
}

struct SelectGoalIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource {
        "Goal"
    }

    static var description: IntentDescription {
        "Shows progress toward a savings goal."
    }

    @Parameter(title: "Goal")
    var goal: GoalEntity?
}

struct SelectBudgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource {
        "Budget"
    }

    static var description: IntentDescription {
        "Shows a budget's spending this period."
    }

    @Parameter(title: "Budget")
    var budget: BudgetEntity?
}
