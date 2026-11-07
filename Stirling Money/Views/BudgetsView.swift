import SwiftData
import SwiftUI

/// Every budget with what's been spent in its current period.
struct BudgetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Budget.name) private var budgets: [Budget]
    /// Needed for all-spending budgets, which count every account.
    @Query private var transactions: [AccountTransaction]

    @State private var isAddingBudget = false
    @State private var editingBudget: Budget?

    var body: some View {
        NavigationStack {
            List {
                ForEach(budgets) { budget in
                    Button {
                        editingBudget = budget
                    } label: {
                        BudgetRow(budget: budget, summary: budget.summary(allTransactions: transactions))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            delete(budget)
                        }
                    }
                    .contextMenu {
                        Button("Edit…", systemImage: "pencil") {
                            afterMenuCloses { editingBudget = budget }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            delete(budget)
                        }
                    }
                }
            }
            .overlay {
                if budgets.isEmpty {
                    ContentUnavailableView(
                        "No Budgets",
                        systemImage: "chart.bar",
                        description: Text("Tap + to set a spending limit for a category or for everything.")
                    )
                }
            }
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Budget", systemImage: "plus") {
                        isAddingBudget = true
                    }
                }
            }
            .sheet(isPresented: $isAddingBudget) {
                BudgetFormView()
            }
            .sheet(item: $editingBudget) { budget in
                BudgetFormView(budget: budget)
            }
        }
    }

    private func delete(_ budget: Budget) {
        withAnimation {
            modelContext.delete(budget)
        }
    }
}

#Preview("With Budgets") {
    BudgetsView()
        .modelContainer(.preview)
}

#Preview("Empty") {
    BudgetsView()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
