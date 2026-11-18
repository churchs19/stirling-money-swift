import SwiftData
import SwiftUI

/// Every savings goal with its progress.
struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Goal.targetDate) private var goals: [Goal]
    @Query private var accounts: [Account]

    @State private var isAddingGoal = false
    @State private var editingGoal: Goal?

    var body: some View {
        NavigationStack {
            List {
                ForEach(goals) { goal in
                    Button {
                        editingGoal = goal
                    } label: {
                        GoalRow(goal: goal)
                            .accessibilityIdentifier("goal.\(goal.name)")
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            delete(goal)
                        }
                    }
                    .contextMenu {
                        Button("Edit…", systemImage: "pencil") {
                            afterMenuCloses { editingGoal = goal }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            delete(goal)
                        }
                    }
                }
            }
            .overlay {
                if goals.isEmpty {
                    if accounts.isEmpty {
                        ContentUnavailableView(
                            "No Goals",
                            systemImage: "flag",
                            description: Text("A goal tracks an account's balance. Add an account first.")
                        )
                    } else {
                        ContentUnavailableView(
                            "No Goals",
                            systemImage: "flag",
                            description: Text("Tap + to save toward a target in one of your accounts.")
                        )
                    }
                }
            }
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Goal", systemImage: "plus") {
                        isAddingGoal = true
                    }
                    .accessibilityIdentifier("addGoal")
                    .disabled(accounts.isEmpty)
                }
            }
            .sheet(isPresented: $isAddingGoal) {
                GoalFormView()
            }
            .sheet(item: $editingGoal) { goal in
                GoalFormView(goal: goal)
            }
        }
    }

    private func delete(_ goal: Goal) {
        withAnimation {
            modelContext.delete(goal)
        }
    }
}

#Preview("With Goals") {
    GoalsView()
        .modelContainer(.preview)
}

#Preview("Empty") {
    GoalsView()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
