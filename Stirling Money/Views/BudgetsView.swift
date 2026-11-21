import SwiftData
import SwiftUI

/// Every budget with what's been spent in its current period.
struct BudgetsView: View {
    @Environment(\.modelContext) private var modelContext
    let book: Book
    @Query private var budgets: [Budget]
    /// Needed for all-spending budgets, which count every account in the book.
    @Query private var transactions: [AccountTransaction]

    @State private var isAddingBudget = false
    @State private var editingBudget: Budget?

    init(book: Book) {
        self.book = book
        _budgets = Query(filter: Budget.inBook(book), sort: \Budget.name)
        _transactions = Query(filter: AccountTransaction.inBook(book))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(budgets) { budget in
                    Button {
                        editingBudget = budget
                    } label: {
                        BudgetRow(budget: budget, summary: budget.summary(allTransactions: transactions))
                            .accessibilityIdentifier("budget.\(budget.name)")
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
            .bookSwitcher(book)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Budget", systemImage: "plus") {
                        isAddingBudget = true
                    }
                    .accessibilityIdentifier("addBudget")
                }
            }
            .sheet(isPresented: $isAddingBudget) {
                BudgetFormView(book: book)
            }
            .sheet(item: $editingBudget) { budget in
                BudgetFormView(book: book, budget: budget)
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
    BudgetsView(book: ModelContainer.preview.firstBook)
        .modelContainer(.preview)
}

#Preview("Empty") {
    let container = ModelContainer.emptyPreview
    BudgetsView(book: container.firstBook)
        .modelContainer(container)
}
