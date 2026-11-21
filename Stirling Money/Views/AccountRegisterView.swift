import SwiftData
import SwiftUI

/// An account's transactions, newest first, with its available and posted balances.
struct AccountRegisterView: View {
    @Environment(\.modelContext) private var modelContext
    let account: Account

    @State private var searchText = ""
    @State private var isEditingAccount = false
    @State private var isAddingTransaction = false
    @State private var editingTransaction: AccountTransaction?
    @State private var recurringForm: RecurringForm?

    /// Which recurring form is open.
    enum RecurringForm: Identifiable {
        case new
        case edit(RecurringTransaction)
        case madeFrom(AccountTransaction)

        var id: String {
            switch self {
            case .new: "new"
            case let .edit(rule): "edit-\(ObjectIdentifier(rule).hashValue)"
            case let .madeFrom(transaction): "from-\(ObjectIdentifier(transaction).hashValue)"
            }
        }
    }

    /// The account's recurring transactions, including transfers into it: active ones by next date, then ended ones.
    private var upcoming: [RecurringTransaction] {
        ((account.recurringTransactions ?? []) + (account.recurringTransfersIn ?? []))
            .sorted { lhs, rhs in
                if lhs.hasEnded() != rhs.hasEnded() {
                    return !lhs.hasEnded()
                }
                return lhs.nextDate < rhs.nextDate
            }
    }

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
                .accessibilityIdentifier("availableBalance")
                LabeledContent("Posted Balance") {
                    AmountText(account.postedBalance)
                }
                .accessibilityIdentifier("postedBalance")
            }

            if searchText.isEmpty, !upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(upcoming) { rule in
                        RecurringRow(rule: rule, account: account)
                            .accessibilityIdentifier("recurring.\(rule.displayPayee(in: account))")
                            .recurringRowActions(rule, context: modelContext) {
                                recurringForm = .edit(rule)
                            }
                    }
                }
            }

            Section {
                if account.transactionCount == 0 {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Tap + to add a transaction.")
                    )
                } else if transactions.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(transactions) { transaction in
                        TransactionRow(transaction: transaction)
                            .accessibilityIdentifier("transaction.\(transaction.displayPayee)")
                            // The posted toggle inside the row is a button of its own,
                            // so a tap gesture (not a row button) opens the editor.
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingTransaction = transaction
                            }
                            .accessibilityAction(named: "Edit") {
                                editingTransaction = transaction
                            }
                            .swipeActions(edge: .leading) {
                                Button(
                                    transaction.isPosted ? "Mark Unposted" : "Mark Posted",
                                    systemImage: transaction.isPosted ? "circle" : "checkmark.circle"
                                ) {
                                    transaction.isPosted.toggle()
                                }
                                .tint(.green)
                                recurringButton(for: transaction)
                                    .tint(.purple)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    delete(transaction)
                                }
                            }
                            // Swipes are awkward with a mouse; Mac and iPad pointer users right-click instead.
                            .contextMenu {
                                Button("Edit…", systemImage: "pencil") {
                                    afterMenuCloses { editingTransaction = transaction }
                                }
                                Button(
                                    transaction.isPosted ? "Mark Unposted" : "Mark Posted",
                                    systemImage: transaction.isPosted ? "circle" : "checkmark.circle"
                                ) {
                                    transaction.isPosted.toggle()
                                }
                                recurringButton(for: transaction, afterMenu: true)
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
                Button("Add Transaction", systemImage: "plus") {
                    isAddingTransaction = true
                }
                .accessibilityIdentifier("addTransaction")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Add Recurring Transaction", systemImage: "repeat") {
                    recurringForm = .new
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Edit Account", systemImage: "pencil") {
                    isEditingAccount = true
                }
            }
        }
        .sheet(isPresented: $isEditingAccount) {
            EditAccountView(account: account)
        }
        .sheet(isPresented: $isAddingTransaction) {
            TransactionFormView(account: account)
        }
        .sheet(item: $editingTransaction) { transaction in
            TransactionFormView(account: account, transaction: transaction)
        }
        .sheet(item: $recurringForm) { form in
            switch form {
            case .new:
                RecurringFormView(draft: RecurringDraft(account: account))
            case let .edit(rule):
                RecurringFormView(editing: rule)
            case let .madeFrom(transaction):
                RecurringFormView(draft: RecurringDraft(from: transaction), madeFrom: transaction)
            }
        }
    }

    /// "Edit Recurring…" for a transaction a rule added, otherwise "Make Recurring…".
    private func recurringButton(for transaction: AccountTransaction, afterMenu: Bool = false) -> some View {
        let form: RecurringForm = transaction.recurrence.map { .edit($0) } ?? .madeFrom(transaction)
        return Button(
            transaction.recurrence == nil ? "Make Recurring…" : "Edit Recurring…",
            systemImage: "repeat"
        ) {
            if afterMenu {
                afterMenuCloses { recurringForm = form }
            } else {
                recurringForm = form
            }
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
        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    )
    let account = Account(name: "New Account", initialBalance: 100)
    container.mainContext.insert(account)
    return NavigationStack {
        AccountRegisterView(account: account)
    }
    .modelContainer(container)
}
