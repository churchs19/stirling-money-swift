import SwiftData
import SwiftUI

/// The list of reports. Every report leaves out transfers between your own accounts.
struct ReportsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    NetIncomeReportView()
                } label: {
                    reportLabel("Net Income", systemImage: "chart.bar.xaxis", detail: "Income vs. expenses each month")
                }
                NavigationLink {
                    CategorySpendingReportView()
                } label: {
                    reportLabel("Spending by Category", systemImage: "chart.pie", detail: "Where the money went")
                }
                NavigationLink {
                    CategoryTrendReportView()
                } label: {
                    reportLabel("Category Over Time", systemImage: "chart.line.uptrend.xyaxis", detail: "One category, month by month")
                }
                NavigationLink {
                    BudgetHistoryReportView()
                } label: {
                    reportLabel("Budget History", systemImage: "chart.bar", detail: "Spending vs. budget for recent periods")
                }
            }
            .navigationTitle("Reports")
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
