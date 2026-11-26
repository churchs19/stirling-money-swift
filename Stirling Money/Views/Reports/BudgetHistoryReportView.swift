import Charts
import SwiftData
import SwiftUI

/// A budget's spending in each of its recent periods, against the budget amount.
struct BudgetHistoryReportView: View {
    @Query private var budgets: [Budget]
    @Query private var transactions: [AccountTransaction]
    @State private var budget: Budget?
    @State private var selectedLabel: String?

    init(book: Book) {
        _budgets = Query(filter: Budget.inBook(book), sort: \Budget.name)
        _transactions = Query(filter: AccountTransaction.inBook(book))
    }

    var body: some View {
        List {
            Section {
                Picker("Budget", selection: $budget) {
                    ForEach(budgets) { budget in
                        Text(budget.name).tag(Optional(budget))
                    }
                }
                if let budget {
                    LabeledContent("Amount") {
                        Text("\(budget.amount, format: .localCurrency) \(budget.period.title.lowercased())")
                            .monospacedDigit()
                    }
                }
            }

            if let budget {
                report(for: budget)
            }
        }
        .overlay {
            if budgets.isEmpty {
                ContentUnavailableView(
                    "No Budgets",
                    systemImage: "chart.bar",
                    description: Text("Add a budget to see how spending compares each period.")
                )
            }
        }
        .navigationTitle("Budget History")
        .onAppear {
            if budget == nil {
                budget = budgets.first
            }
        }
    }

    @ViewBuilder
    private func report(for budget: Budget) -> some View {
        let history = Reports.history(of: budget, allTransactions: transactions)
        let selected = history.first { label(for: $0.interval, period: budget.period) == selectedLabel }

        Section {
            if history.isEmpty {
                ContentUnavailableView(
                    "Not Started",
                    systemImage: "calendar",
                    description: Text("This budget starts \(budget.startDate, format: .dateTime.month(.abbreviated).day().year()).")
                )
            } else {
                Chart {
                    ForEach(history) { period in
                        BarMark(
                            x: .value("Period", label(for: period.interval, period: budget.period)),
                            y: .value("Spent", period.spent.chartValue),
                            // A fixed width, so one or two periods don't become slabs.
                            width: .fixed(24)
                        )
                        .cornerRadius(4)
                        .foregroundStyle(ChartPalette.series[0])
                    }
                    RuleMark(y: .value("Budget", budget.amount.chartValue))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    if let selected {
                        RuleMark(x: .value("Period", label(for: selected.interval, period: budget.period)))
                            .foregroundStyle(.secondary.opacity(0.3))
                            .zIndex(-1)
                            .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                ChartCallout {
                                    Text(selected.interval.formattedDays()).bold()
                                    Text("Spent \(selected.spent, format: .localCurrency)")
                                }
                            }
                    }
                }
                .chartXSelection(value: $selectedLabel)
                .currencyYAxis()
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                    }
                }
                .frame(height: 240)
                .padding(.vertical, 8)
            }
        } footer: {
            Text("The last ^[\(history.count) period](inflect: true). The dashed line is the budget amount.")
        }

        if !history.isEmpty {
            Section("By Period") {
                ForEach(history.reversed()) { period in
                    HStack(alignment: .firstTextBaseline) {
                        Text(period.interval.formattedDays())
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            AmountText(period.spent)
                            if period.spent > budget.amount {
                                Label("\(period.spent - budget.amount, format: .localCurrency) over", systemImage: "exclamationmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else {
                                Text("\(budget.amount - period.spent, format: .localCurrency) under")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// A short, unique label for a period on the chart's x-axis.
    private func label(for interval: DateInterval, period: BudgetPeriod) -> String {
        switch period {
        case .weekly, .custom: interval.start.formatted(.dateTime.month(.abbreviated).day())
        case .monthly: interval.start.formatted(.dateTime.month(.abbreviated))
        case .yearly: interval.start.formatted(.dateTime.year())
        }
    }
}

#Preview {
    NavigationStack {
        BudgetHistoryReportView(book: ModelContainer.preview.firstBook)
    }
    .modelContainer(.preview)
}
