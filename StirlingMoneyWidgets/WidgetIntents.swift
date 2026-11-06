import AppIntents
import WidgetKit

/// An account a widget can show, read from the snapshot.
struct AccountEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Account"
    }

    static var defaultQuery = AccountQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct AccountQuery: EntityQuery {
    func entities(for identifiers: [AccountEntity.ID]) async throws -> [AccountEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AccountEntity] {
        (WidgetSnapshot.load()?.accounts ?? []).map { AccountEntity(id: $0.id, name: $0.name) }
    }
}

/// A goal a widget can show, read from the snapshot.
struct GoalEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Goal"
    }

    static var defaultQuery = GoalQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct GoalQuery: EntityQuery {
    func entities(for identifiers: [GoalEntity.ID]) async throws -> [GoalEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [GoalEntity] {
        (WidgetSnapshot.load()?.goals ?? []).map { GoalEntity(id: $0.id, name: $0.name) }
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
