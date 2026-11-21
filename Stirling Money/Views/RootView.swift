import SwiftData
import SwiftUI

/// The app's top level: Accounts, Budgets, Goals and Reports for the current book. Settings opens from the Accounts ⋯
/// menu. A tab bar on iPhone; a sidebar on iPad and Mac.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @SceneStorage("selectedTab") private var selectedTab: AppTab = .accounts
    @State private var accountPath: [Account] = []
    @Query(sort: Book.order) private var books: [Book]
    @AppStorage(Books.currentKey) private var currentBookID = ""

    private var book: Book? {
        Books.current(id: currentBookID, in: books)
    }

    var body: some View {
        if let book {
            tabs(book)
        } else {
            // Only until `Books.prepare` makes the first book.
            ProgressView()
                .task { _ = try? Books.prepare(in: modelContext) }
        }
    }

    private func tabs(_ book: Book) -> some View {
        TabView(selection: $selectedTab) {
            // Each tab's queries are made for one book, so a new book gets new views (`id`).
            Tab("Accounts", systemImage: "banknote", value: AppTab.accounts) {
                AccountsView(book: book, path: $accountPath)
                    .id(book.syncID)
            }
            Tab("Budgets", systemImage: "chart.bar", value: AppTab.budgets) {
                BudgetsView(book: book)
                    .id(book.syncID)
            }
            Tab("Goals", systemImage: "flag", value: AppTab.goals) {
                GoalsView(book: book)
                    .id(book.syncID)
            }
            Tab("Reports", systemImage: "chart.pie", value: AppTab.reports) {
                ReportsView(book: book)
                    .id(book.syncID)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .onOpenURL(perform: open)
        .onChange(of: book.syncID) {
            // Leave the other book's accounts, and show the new book on the widgets and the Watch.
            accountPath.removeAll { $0.book?.syncID != book.syncID }
            WidgetSnapshotWriter.scheduleUpdate()
        }
    }

    /// Opens a link from a widget. Links to accounts that no longer exist open the accounts list.
    private func open(_ url: URL) {
        switch DeepLink(url: url) {
        case let .account(id):
            selectedTab = .accounts
            let accounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
            let account = DeepLink.account(withWidgetID: id, in: accounts)
            // The widget may have been drawn for another book.
            if let accountBook = account?.book {
                currentBookID = accountBook.syncID
            }
            accountPath = account.map { [$0] } ?? []
        case .goals:
            selectedTab = .goals
        case .budgets:
            selectedTab = .budgets
        case nil:
            break
        }
    }
}

enum AppTab: String {
    case accounts, budgets, goals, reports
}

#Preview {
    RootView()
        .environment(AppLock())
        .modelContainer(.preview)
}
