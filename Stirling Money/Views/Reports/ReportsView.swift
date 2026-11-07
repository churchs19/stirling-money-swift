import SwiftData
import SwiftUI

/// The list of reports. Every report leaves out transfers between your own accounts.
struct ReportsView: View {
    @State private var path: [Report] = []

    enum Report: Hashable {
        case netIncome, categorySpending, categoryTrend, budgetHistory
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                NavigationRow(value: Report.netIncome, path: $path) {
                    reportLabel("Net Income", systemImage: "chart.bar.xaxis", detail: "Income vs. expenses each month")
                }
                NavigationRow(value: Report.categorySpending, path: $path) {
                    reportLabel("Spending by Category", systemImage: "chart.pie", detail: "Where the money went")
                }
                NavigationRow(value: Report.categoryTrend, path: $path) {
                    reportLabel("Category Over Time", systemImage: "chart.line.uptrend.xyaxis", detail: "One category, month by month")
                }
                NavigationRow(value: Report.budgetHistory, path: $path) {
                    reportLabel("Budget History", systemImage: "chart.bar", detail: "Spending vs. budget for recent periods")
                }
            }
            .navigationTitle("Reports")
            .navigationDestination(for: Report.self) { report in
                switch report {
                case .netIncome: NetIncomeReportView()
                case .categorySpending: CategorySpendingReportView()
                case .categoryTrend: CategoryTrendReportView()
                case .budgetHistory: BudgetHistoryReportView()
                }
            }
        }
    }

    private func reportLabel(_ title: LocalizedStringKey, systemImage: String, detail: LocalizedStringKey) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

#Preview {
    ReportsView()
        .modelContainer(.preview)
}
