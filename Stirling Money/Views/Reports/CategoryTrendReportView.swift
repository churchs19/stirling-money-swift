import Charts
import SwiftData
import SwiftUI

/// One category's spending per month.
struct CategoryTrendReportView: View {
    @Query private var categories: [Category]
    @AppStorage("reportRange") private var range: ReportRange = .sixMonths
    @State private var category: Category?
    @State private var selectedDate: Date?

    private var sortedCategories: [Category] {
        categories.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                Picker("Category", selection: $category) {
                    ForEach(sortedCategories) { category in
                        Text(category.name).tag(Optional(category))
                    }
                }
                ReportRangePicker(range: $range)
            }

            if let category {
                report(for: category)
            }
        }
        .overlay {
            if categories.isEmpty {
                ContentUnavailableView(
                    "No Categories",
                    systemImage: "tag",
                    description: Text("Give transactions a category to see spending over time.")
                )
            }
        }
        .navigationTitle("Category Over Time")
        .onAppear {
            if category == nil {
                category = sortedCategories.first
            }
        }
    }

    @ViewBuilder
    private func report(for category: Category) -> some View {
        let amounts = Reports.spending(in: category, months: range.rawValue)
        let selected = selectedDate.flatMap { date in
            amounts.first { Calendar.current.isDate($0.month, equalTo: date, toGranularity: .month) }
        }

        Section {
            Chart {
                ForEach(amounts) { month in
                    BarMark(
                        x: .value("Month", month.month, unit: .month),
                        y: .value("Spent", month.amount.chartValue),
                        width: .ratio(0.6)
                    )
                    .cornerRadius(4)
                    .foregroundStyle(ChartPalette.series[0])
                }
                if let selected {
                    RuleMark(x: .value("Month", selected.month, unit: .month))
                        .foregroundStyle(.secondary.opacity(0.3))
                        .zIndex(-1)
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ChartCallout {
                                Text(selected.month.monthAndYear).bold()
                                Text(selected.amount, format: .localCurrency)
                            }
                        }
                }
            }
            .chartXSelection(value: $selectedDate)
            .currencyYAxis()
            .monthXAxis()
            .frame(height: 240)
            .padding(.vertical, 8)
        } footer: {
            Text("Spending less refunds in \(category.name) each month.")
        }

        Section("By Month") {
            ForEach(amounts.reversed()) { month in
                LabeledContent(month.month.monthAndYear) {
                    AmountText(month.amount)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CategoryTrendReportView()
    }
    .modelContainer(.preview)
}
