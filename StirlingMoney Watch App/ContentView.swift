import SwiftUI

/// The Watch app: Accounts, Budgets and Goals as vertical pages, from the summary the iPhone sends.
struct ContentView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        Group {
            if let summary = store.snapshot {
                // Recurring transactions the iPhone hasn't added yet count from the day they fall due
                // (`projected(on:)`), checked every hour while the app is open. The schedule starts at a fixed
                // time (today's midnight): starting it at `.now` would make each redraw a new schedule, and so
                // another redraw, without end.
                TimelineView(.periodic(from: Calendar.current.startOfDay(for: .now), by: 3600)) { context in
                    pages(summary.projected(on: context.date))
                }
            } else {
                ContentUnavailableView(
                    "No Data Yet",
                    systemImage: "iphone",
                    description: Text("Open Stirling Money on your iPhone.")
                )
            }
        }
        .tint(store.accent)
    }

    /// Accounts, Budgets and Goals as vertical pages.
    private func pages(_ snapshot: WidgetSnapshot) -> some View {
        NavigationStack {
            TabView {
                AccountsPage(snapshot: snapshot)
                BudgetsPage(budgets: snapshot.budgets)
                GoalsPage(goals: snapshot.goals)
            }
            .tabViewStyle(.verticalPage)
            .navigationDestination(for: WidgetSnapshot.AccountSummary.self) { account in
                AccountDetailView(account: account)
            }
        }
    }
}

/// "Updated 5 min ago" at the foot of each page: how current the iPhone's figures are.
struct UpdatedFooter: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        if let asOf = store.asOf {
            // "Updated now", "Updated 5 minutes ago": redrawn each minute.
            TimelineView(.everyMinute) { _ in
                Text("Updated \(asOf, format: .relative(presentation: .named, unitsStyle: .wide))")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview("Summary") {
    ContentView()
        .environment(WatchStore(fileURL: nil, snapshot: .sample))
}

#Preview("No Data") {
    ContentView()
        .environment(WatchStore(fileURL: nil))
}
