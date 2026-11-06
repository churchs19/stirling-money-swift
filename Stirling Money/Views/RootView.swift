import SwiftData
import SwiftUI

/// The app's top level: Accounts, Budgets and Goals. A tab bar on iPhone; a sidebar on iPad and Mac.
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
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

enum AppTab: String {
    case accounts, budgets, goals
}

#Preview {
    RootView()
        .modelContainer(.preview)
}
