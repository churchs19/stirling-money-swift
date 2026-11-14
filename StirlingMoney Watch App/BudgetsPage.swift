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
        VStack(alignment: .leading, spacing: 4) {
            Text(budget.name)
                .font(.headline)
            Text(budget.categoryName ?? String(localized: "All Spending"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            if budget.isCurrent(on: now) {
                ProgressView(value: budget.progress)
                    .tint(budget.isOverBudget ? .red : store.accent)
                    .accessibilityHidden(true)
                if budget.isOverBudget {
                    Text("\(-budget.remaining, format: .localCurrency) over")
                        .foregroundStyle(.red)
                } else {
                    Text("\(budget.remaining, format: .localCurrency) left")
                }
                Text(periodText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                // The iPhone worked these figures out for a period that has since ended.
                Text("Open Stirling Money on your iPhone to update.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// "Nov 1 – 30": the period's first and last days (`periodEnd` is the day after the last).
    private var periodText: String {
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: budget.periodEnd) ?? budget.periodEnd
        return (budget.periodStart ..< lastDay).formatted(.interval.month(.abbreviated).day())
    }
}

#Preview {
    NavigationStack {
        BudgetsPage(budgets: WidgetSnapshot.sample.budgets)
    }
    .environment(WatchStore(fileURL: nil, snapshot: .sample))
}
