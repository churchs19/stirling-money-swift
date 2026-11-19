import SwiftData
import SwiftUI

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    /// The accounts open in the stack, so a widget link can open one directly.
    @Binding var path: [Account]
    @Query private var accounts: [Account]
    @AppStorage("accountSort") private var sort: AccountSort = .name
    @AppStorage("accountLayout") private var layout: AccountLayout = .tiles

    @State private var isAddingAccount = false
    @State private var isShowingCategories = false
    @State private var isShowingRecurring = false
    @State private var isShowingSettings = false
    @State private var accountPendingDeletion: Account?

    var body: some View {
        let sortedAccounts = sort.sorted(accounts)

        NavigationStack(path: $path) {
            Group {
                switch layout {
                case .tiles: tiles(sortedAccounts)
                case .list: list(sortedAccounts)
                }
            }
            .overlay {
                if accounts.isEmpty {
                    ContentUnavailableView(
                        "No Accounts",
                        systemImage: "banknote",
                        description: Text("Tap + to add your first account.")
                    )
                }
            }
            .navigationTitle("Accounts")
            .navigationDestination(for: Account.self) { account in
                AccountRegisterView(account: account)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Account", systemImage: "plus") {
                        isAddingAccount = true
                    }
                    .accessibilityIdentifier("addAccount")
                }
                ToolbarItem(placement: .primaryAction) {
                    // Shows the layout it switches to.
                    Button(layout.toggled.switchTitle, systemImage: layout.toggled.systemImage) {
                        withAnimation {
                            layout = layout.toggled
                        }
                    }
                    .help(layout.toggled.switchTitle)
                    .accessibilityIdentifier("toggleLayout")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Recurring", systemImage: "repeat") {
                        isShowingRecurring = true
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Categories", systemImage: "tag") {
                        isShowingCategories = true
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Picker("Sort By", systemImage: "arrow.up.arrow.down", selection: $sort) {
                        ForEach(AccountSort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    #if os(macOS)
                        // Opens the app's Settings window, the same as ⌘,.
                        SettingsLink {
                            Label("Settings", systemImage: "gear")
                        }
                    #else
                        Button("Settings", systemImage: "gear") {
                            isShowingSettings = true
                        }
                    #endif
                }
            }
            .sheet(isPresented: $isAddingAccount) {
                NewAccountView()
            }
            .sheet(isPresented: $isShowingSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isShowingSettings = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $isShowingRecurring) {
                NavigationStack {
                    RecurringListView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isShowingRecurring = false }
                            }
                        }
                }
                #if os(macOS)
                .frame(minWidth: 460, minHeight: 420)
                #endif
            }
            .sheet(isPresented: $isShowingCategories) {
                NavigationStack {
                    CategoriesView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isShowingCategories = false }
                            }
                        }
                }
                #if os(macOS)
                .frame(minWidth: 400, minHeight: 400)
                #endif
            }
            .confirmationDialog(
                accountPendingDeletion.map { "Delete \($0.name)?" } ?? "",
                isPresented: Binding(
                    get: { accountPendingDeletion != nil },
                    set: {
                        if !$0 {
                            accountPendingDeletion = nil
                        }
                    }
                ),
                titleVisibility: .visible,
                presenting: accountPendingDeletion
            ) { account in
                Button("Delete Account", role: .destructive) {
                    withAnimation {
                        modelContext.delete(account)
                    }
                }
            } message: { account in
                deletionMessage(for: account)
            }
        }
    }

    // MARK: Layouts

    private func tiles(_ accounts: [Account]) -> some View {
        ScrollView {
            if !accounts.isEmpty {
                LabeledContent("Total") {
                    AmountText(accounts.reduce(0) { $0 + $1.balance })
                }
                .bold()
                .accessibilityIdentifier("accountsTotal")
                // A card like the list layout's Total row.
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.groupedItemBackground, in: RoundedRectangle(cornerRadius: 20))
                .padding(.bottom, 12)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(accounts) { account in
                    // A button rather than a NavigationLink, which also works on the Mac (see NavigationRow).
                    Button {
                        path.append(account)
                    } label: {
                        AccountTile(account: account)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("account.\(account.name)")
                    .contextMenu {
                        Button("Delete Account…", systemImage: "trash", role: .destructive) {
                            afterMenuCloses { accountPendingDeletion = account }
                        }
                    }
                }
            }
        }
        .contentMargins(16, for: .scrollContent)
        // Matches the list layout's page.
        .background(Color.groupedPageBackground)
    }

    private func list(_ sortedAccounts: [Account]) -> some View {
        List {
            if !sortedAccounts.isEmpty {
                Section {
                    LabeledContent("Total") {
                        AmountText(sortedAccounts.reduce(0) { $0 + $1.balance })
                    }
                    .bold()
                    .accessibilityIdentifier("accountsTotal")
                }

                Section {
                    ForEach(sortedAccounts) { account in
                        NavigationRow(value: account, path: $path) {
                            LabeledContent {
                                AmountText(account.balance)
                            } label: {
                                Label {
                                    Text(account.name)
                                } icon: {
                                    if let iconName = account.iconName {
                                        AccountIconView(iconName: iconName)
                                    }
                                }
                            }
                        }
                        .accessibilityIdentifier("account.\(account.name)")
                        .contextMenu {
                            Button("Delete Account…", systemImage: "trash", role: .destructive) {
                                afterMenuCloses { accountPendingDeletion = account }
                            }
                        }
                    }
                    .onDelete { offsets in
                        accountPendingDeletion = offsets.first.map { sortedAccounts[$0] }
                    }
                }
            }
        }
    }

    private func deletionMessage(for account: Account) -> Text {
        let transactions = account.transactionCount
        let goals = account.goals?.count ?? 0
        if goals > 0 {
            return Text("This also deletes ^[\(transactions) transaction](inflect: true) and ^[\(goals) goal](inflect: true). Transfers stay in the other accounts.")
        }
        return Text("This also deletes ^[\(transactions) transaction](inflect: true). Transfers stay in the other accounts.")
    }
}

#Preview("With Accounts") {
    @Previewable @State var path: [Account] = []
    AccountsView(path: $path)
        .environment(AppLock())
        .modelContainer(.preview)
}

#Preview("Empty") {
    @Previewable @State var path: [Account] = []
    AccountsView(path: $path)
        .modelContainer(for: AppSchema.models, inMemory: true)
}
