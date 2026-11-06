import Charts
import SwiftData
import SwiftUI

/// Income vs. expenses per month, across all accounts.
struct NetIncomeReportView: View {
    @Query private var transactions: [AccountTransaction]
    @AppStorage("reportRange") private var range: ReportRange = .sixMonths
    @State private var selectedDate: Date?

    private struct Bar: Identifiable {
        let month: Date
        let series: String
        let amount: Decimal
        var id: String {
            "\(month.timeIntervalSinceReferenceDate)-\(series)"
        }
    }

    private static let incomeLabel = String(localized: "Income")
    private static let expensesLabel = String(localized: "Expenses")

    var body: some View {
        let totals = Reports.incomeAndExpenses(transactions, months: range.rawValue)

        List {
            Section {
                ReportRangePicker(range: $range)
                chart(totals)
            } footer: {
                Text("Transfers between your accounts aren't counted.")
            }

            Section("By Month") {
                ForEach(totals.reversed()) { total in
                    row(total)
                }
            }
        }
        .navigationTitle("Net Income")
    }

    private func chart(_ totals: [MonthTotal]) -> some View {
        let bars: [Bar] = totals.flatMap { total in
            [
                Bar(month: total.month, series: Self.incomeLabel, amount: total.income),
                Bar(month: total.month, series: Self.expensesLabel, amount: total.expenses),
            ]
        }
        let selected: MonthTotal? = selectedDate.flatMap { date in
            totals.first { Calendar.current.isDate($0.month, equalTo: date, toGranularity: .month) }
        }

        return Chart {
            ForEach(bars) { bar in
                BarMark(
                    x: .value("Month", bar.month, unit: .month),
                    y: .value("Amount", bar.amount.chartValue),
                    width: .ratio(0.8)
                )
                .cornerRadius(4)
                .foregroundStyle(by: .value("Type", bar.series))
                .position(by: .value("Type", bar.series))
            }
            if let selected {
                RuleMark(x: .value("Month", selected.month, unit: .month))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .zIndex(-1)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        callout(for: selected)
                    }
            }
        }
        .chartForegroundStyleScale([Self.incomeLabel: ChartPalette.series[0], Self.expensesLabel: ChartPalette.series[1]])
        .chartXSelection(value: $selectedDate)
        .currencyYAxis()
        .monthXAxis()
        .frame(height: 260)
        .padding(.vertical, 8)
    }

    private func callout(for total: MonthTotal) -> some View {
        ChartCallout {
            Text(total.month.monthAndYear).bold()
            Text("Income \(total.income, format: .localCurrency)")
            Text("Expenses \(total.expenses, format: .localCurrency)")
            Text("Net \(total.net, format: .localCurrency)")
        }
    }

    private func row(_ total: MonthTotal) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(total.month.monthAndYear)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(total.net)
                    .bold()
                Text("In \(total.income, format: .localCurrency) · Out \(total.expenses, format: .localCurrency)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        NetIncomeReportView()
    }
    .modelContainer(.preview)
}
