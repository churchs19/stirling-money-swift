import SwiftData
import SwiftUI

/// A budget card: what it covers, spent vs. limit for the current period, and what's left.
struct BudgetRow: View {
    let budget: Budget
    let summary: BudgetSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(budget.name)
                    .font(.headline)
                Spacer()
                Text(budget.category?.name ?? String(localized: "All Spending"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            switch summary.state {
            case let .active(period):
                ProgressView(value: summary.progress)
                    .tint(summary.isOverBudget ? .red : .accentColor)
                    .accessibilityHidden(true)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(summary.spent, format: .localCurrency) of \(summary.amount, format: .localCurrency)")
                        .monospacedDigit()
                    Spacer()
                    if summary.isOverBudget {
                        Text("\(-summary.remaining, format: .localCurrency) over")
                            .monospacedDigit()
                            .foregroundStyle(.red)
                    } else {
                        Text("\(summary.remaining, format: .localCurrency) left")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                Text("\(budget.period.title) · \(period.formattedDays())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .notStarted:
                Text("Starts \(budget.startDate, format: .dateTime.month(.abbreviated).day().year())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .ended:
                Text("Ended")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        // Otherwise the separator lines up with the first text after an icon, such as "Reached".
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let container = ModelContainer.preview
    let budgets = try! container.mainContext.fetch(FetchDescriptor<Budget>())
    let transactions = try! container.mainContext.fetch(FetchDescriptor<AccountTransaction>())
    return List(budgets) { budget in
        BudgetRow(budget: budget, summary: budget.summary(allTransactions: transactions))
    }
    .modelContainer(container)
}
