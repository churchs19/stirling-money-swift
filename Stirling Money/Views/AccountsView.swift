import SwiftData
import SwiftUI

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [Account]
    @AppStorage("accountSort") private var sort: AccountSort = .name

    @State private var isAddingAccount = false
    @State private var isShowingCategories = false
    @State private var accountPendingDeletion: Account?

    var body: some View {
        let sortedAccounts = sort.sorted(accounts)

        NavigationStack {
            List {
                if !accounts.isEmpty {
                    Section {
                        ForEach(sortedAccounts) { account in
                            NavigationLink(value: account) {
                                LabeledContent(account.name) {
                                    AmountText(account.balance)
                                }
                            }
                            .contextMenu {
                                Button("Delete Account…", systemImage: "trash", role: .destructive) {
                                    accountPendingDeletion = account
                                }
                            }
                        }
                        .onDelete { offsets in
                            accountPendingDeletion = offsets.first.map { sortedAccounts[$0] }
                        }
                    }

                    Section {
                        LabeledContent("Total") {
                            AmountText(accounts.reduce(0) { $0 + $1.balance })
                        }
                        .bold()
                    }
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
            }
            .sheet(isPresented: $isAddingAccount) {
                NewAccountView()
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
    AccountsView()
        .modelContainer(.preview)
}

#Preview("Empty") {
    AccountsView()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
