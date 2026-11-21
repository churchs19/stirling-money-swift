import SwiftData
import SwiftUI

/// Every recurring transaction across accounts, grouped by account or in order of their next date.
struct RecurringListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var rules: [RecurringTransaction]
    @Query private var accounts: [Account]

    init(book: Book) {
        _rules = Query(filter: RecurringTransaction.inBook(book))
        _accounts = Query(filter: Account.inBook(book))
    }
    @AppStorage("recurringGrouping") private var grouping: Grouping = .account

    @State private var editingRule: RecurringTransaction?
    @State private var isAdding = false

    enum Grouping: String, CaseIterable, Identifiable {
        case account
        case nextDate

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .account: String(localized: "By Account")
            case .nextDate: String(localized: "By Next Date")
            }
        }
    }

    /// Active rules by next date, then ended ones.
    private func ordered(_ rules: [RecurringTransaction]) -> [RecurringTransaction] {
        rules.sorted { lhs, rhs in
            if lhs.hasEnded() != rhs.hasEnded() {
                return !lhs.hasEnded()
            }
            return lhs.nextDate < rhs.nextDate
        }
    }

    var body: some View {
        List {
            switch grouping {
            case .account:
                ForEach(AccountSort.name.sorted(accounts.filter { !($0.recurringTransactions ?? []).isEmpty })) { account in
                    Section(account.name) {
                        ForEach(ordered(account.recurringTransactions ?? [])) { rule in
                            row(rule, showsAccount: false)
                        }
                    }
                }
            case .nextDate:
                ForEach(ordered(rules)) { rule in
                    row(rule, showsAccount: true)
                }
            }
        }
        .overlay {
            if rules.isEmpty {
                ContentUnavailableView(
                    "No Recurring Transactions",
                    systemImage: "repeat",
                    description: Text("Add rent, pay or a regular transfer, and it's added on its schedule.")
                )
            }
        }
        .navigationTitle("Recurring")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Recurring Transaction", systemImage: "plus") {
                    isAdding = true
                }
                .disabled(accounts.isEmpty)
                .accessibilityIdentifier("addRecurring")
            }
            ToolbarItem(placement: .secondaryAction) {
                Picker("Show", systemImage: "list.bullet.indent", selection: $grouping) {
                    ForEach(Grouping.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            RecurringFormView(draft: RecurringDraft(account: AccountSort.name.sorted(accounts).first))
        }
        .sheet(item: $editingRule) { rule in
            RecurringFormView(editing: rule)
        }
    }

    private func row(_ rule: RecurringTransaction, showsAccount: Bool) -> some View {
        RecurringRow(rule: rule, account: rule.account, showsAccount: showsAccount)
            .accessibilityIdentifier("recurring.\(rule.displayPayee)")
            .recurringRowActions(rule, context: modelContext) {
                editingRule = rule
            }
    }
}

#Preview {
    NavigationStack {
        RecurringListView(book: ModelContainer.preview.firstBook)
    }
    .modelContainer(.preview)
}
