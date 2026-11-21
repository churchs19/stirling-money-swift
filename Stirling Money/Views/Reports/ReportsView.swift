import SwiftData
import SwiftUI

/// The list of reports. Every report leaves out transfers between your own accounts.
struct ReportsView: View {
    /// The book reported on.
    let book: Book
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
                .accessibilityIdentifier("report.netIncome")
                NavigationRow(value: Report.categorySpending, path: $path) {
                    reportLabel("Spending by Category", systemImage: "chart.pie", detail: "Where the money went")
                }
                .accessibilityIdentifier("report.categorySpending")
                NavigationRow(value: Report.categoryTrend, path: $path) {
                    reportLabel("Category Over Time", systemImage: "chart.line.uptrend.xyaxis", detail: "One category, month by month")
                }
                .accessibilityIdentifier("report.categoryTrend")
                NavigationRow(value: Report.budgetHistory, path: $path) {
                    reportLabel("Budget History", systemImage: "chart.bar", detail: "Spending vs. budget for recent periods")
                }
                .accessibilityIdentifier("report.budgetHistory")
            }
            .navigationTitle("Reports")
            .bookSwitcher(book)
            .navigationDestination(for: Report.self) { report in
                switch report {
                case .netIncome: NetIncomeReportView(book: book)
                case .categorySpending: CategorySpendingReportView(book: book)
                case .categoryTrend: CategoryTrendReportView(book: book)
                case .budgetHistory: BudgetHistoryReportView(book: book)
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
    ReportsView(book: ModelContainer.preview.firstBook)
        .modelContainer(.preview)
}
