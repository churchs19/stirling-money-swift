import SwiftData
import SwiftUI

/// The app's top level: Accounts, Budgets, Goals and Reports. A tab bar on iPhone; a sidebar on iPad and Mac.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @SceneStorage("selectedTab") private var selectedTab: AppTab = .accounts
    @State private var accountPath: [Account] = []

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Accounts", systemImage: "banknote", value: AppTab.accounts) {
                AccountsView(path: $accountPath)
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
            // The Mac has a Settings window (⌘,) instead.
            #if !os(macOS)
                Tab("Settings", systemImage: "gear", value: AppTab.settings) {
                    NavigationStack {
                        SettingsView()
                    }
                }
            #endif
        }
        .tabViewStyle(.sidebarAdaptable)
        .onOpenURL(perform: open)
    }

    /// Opens a link from a widget. Links to accounts that no longer exist open the accounts list.
    private func open(_ url: URL) {
        switch DeepLink(url: url) {
        case let .account(id):
            selectedTab = .accounts
            let accounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
            if let account = accounts.first(where: { WidgetSnapshot.widgetID(for: $0) == id }) {
                accountPath = [account]
            } else {
                accountPath = []
            }
        case .goals:
            selectedTab = .goals
        case nil:
            break
        }
    }
}

enum AppTab: String {
    case accounts, budgets, goals, reports, settings
}

#Preview {
    RootView()
        .environment(AppLock())
        .modelContainer(.preview)
}
