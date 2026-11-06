import SwiftData
import SwiftUI

/// The app's top level: Accounts, Budgets, Goals and Reports. A tab bar on iPhone; a sidebar on iPad and Mac.
struct RootView: View {
    @SceneStorage("selectedTab") private var selectedTab: AppTab = .accounts

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Accounts", systemImage: "banknote", value: AppTab.accounts) {
                AccountsView()
            }
            Tab("Budgets", systemImage: "chart.bar", value: AppTab.budgets) {
                BudgetsView()
            }
            Tab("Goals", systemImage: "flag", value: AppTab.goals) {
                GoalsView()
            }
            Tab("Reports", systemImage: "chart.pie", value: AppTab.reports) {
                ReportsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

enum AppTab: String {
    case accounts, budgets, goals, reports
}

#Preview {
    RootView()
        .modelContainer(.preview)
}
