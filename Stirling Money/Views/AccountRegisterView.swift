import SwiftData
import SwiftUI

/// An account's transactions, newest first, with its available and posted balances.
struct AccountRegisterView: View {
    @Environment(\.modelContext) private var modelContext
    let account: Account

    @State private var searchText = ""
    @State private var isEditingAccount = false

    private var visibleTransactions: [AccountTransaction] {
        (account.transactions ?? [])
            .filter { $0.matches(searchText: searchText) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        let transactions = visibleTransactions

        List {
            Section {
                LabeledContent("Available Balance") {
                    AmountText(account.balance)
                }
                LabeledContent("Posted Balance") {
                    AmountText(account.postedBalance)
                }
            }

            Section {
                if account.transactionCount == 0 {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Transactions you add to this account will appear here.")
                    )
                } else if transactions.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(transactions) { transaction in
                        TransactionRow(transaction: transaction)
                            .swipeActions(edge: .leading) {
                                Button(
                                    transaction.isPosted ? "Mark Unposted" : "Mark Posted",
                                    systemImage: transaction.isPosted ? "circle" : "checkmark.circle"
                                ) {
                                    transaction.isPosted.toggle()
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    delete(transaction)
                                }
                            }
                            // Swipes are awkward with a mouse; Mac and iPad pointer users right-click instead.
                            .contextMenu {
                                Button(
                                    transaction.isPosted ? "Mark Unposted" : "Mark Posted",
                                    systemImage: transaction.isPosted ? "circle" : "checkmark.circle"
                                ) {
                                    transaction.isPosted.toggle()
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    delete(transaction)
                                }
                            }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search Transactions")
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit Account", systemImage: "pencil") {
                    isEditingAccount = true
                }
            }
        }
        .sheet(isPresented: $isEditingAccount) {
            EditAccountView(account: account)
        }
    }

    private func delete(_ transaction: AccountTransaction) {
        withAnimation {
            Ledger.delete(transaction, in: modelContext)
        }
    }
}

#Preview("With Transactions") {
    let container = ModelContainer.preview
    let checking = try! container.mainContext.fetch(
        FetchDescriptor<Account>(predicate: #Predicate { $0.name == "Checking" })
    ).first!
    return NavigationStack {
        AccountRegisterView(account: checking)
    }
    .modelContainer(container)
}

#Preview("Empty") {
    let container = try! ModelContainer(
        for: Schema(AppSchema.models),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let account = Account(name: "New Account", initialBalance: 100)
    container.mainContext.insert(account)
    return NavigationStack {
        AccountRegisterView(account: account)
    }
    .modelContainer(container)
}
