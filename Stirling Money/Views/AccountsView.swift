import SwiftData
import SwiftUI

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.name) private var accounts: [Account]
    @State private var isAddingAccount = false

    private let currencyCode = Locale.current.currency?.identifier ?? "USD"

    var body: some View {
        NavigationStack {
            List {
                ForEach(accounts) { account in
                    HStack {
                        Text(account.name)
                        Spacer()
                        Text(account.balance, format: .currency(code: currencyCode))
                            .monospacedDigit()
                            .foregroundStyle(account.balance < 0 ? .red : .primary)
                    }
                }
                .onDelete(perform: deleteAccounts)
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Account", systemImage: "plus") {
                        isAddingAccount = true
                    }
                }
            }
            .sheet(isPresented: $isAddingAccount) {
                NewAccountView()
            }
        }
    }

    private func deleteAccounts(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(accounts[index])
            }
        }
    }
}

#Preview("With Accounts") {
    let container = try! ModelContainer(
        for: Account.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(Account(name: "Checking", initialBalance: 1250.75))
    container.mainContext.insert(Account(name: "Savings", initialBalance: 8000))
    container.mainContext.insert(Account(name: "Credit Card", initialBalance: -342.18))
    return AccountsView()
        .modelContainer(container)
}

#Preview("Empty") {
    AccountsView()
        .modelContainer(for: Account.self, inMemory: true)
}
