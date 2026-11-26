import SwiftUI

/// Each budget in its current period: spent against the limit, and what's left or over.
struct BudgetsPage: View {
    let budgets: [WidgetSnapshot.BudgetSummary]

    var body: some View {
        List {
            if budgets.isEmpty {
                Text("No budgets in a current period.")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    // Redraws at midnight, so a period that has ended stops showing last period's figures.
                    TimelineView(.everyMinute) { context in
                        ForEach(budgets) { budget in
                            BudgetRow(budget: budget, now: context.date)
                        }
                    }
                } header: {
                    BookHeader()
                } footer: {
                    UpdatedFooter()
                }
            }
        }
        .navigationTitle("Budgets")
    }
}

private struct BudgetRow: View {
    @Environment(WatchStore.self) private var store
    let budget: WidgetSnapshot.BudgetSummary
    let now: Date

    var body: some View {
        BudgetSummaryCard(budget: budget, accent: store.accent, style: .compact, now: now)
            .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        BudgetsPage(budgets: WidgetSnapshot.sample.budgets)
    }
    .environment(WatchStore(fileURL: nil, snapshot: .sample))
}
