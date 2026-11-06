import SwiftData
import SwiftUI

/// Adds a transaction to an account, or edits one. The fields change with the kind:
/// a check has a number, a transfer has the other account instead of a payee and category.
struct TransactionFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]
    @Query private var categories: [Category]

    let account: Account
    /// The entry being edited, or nil for a new one.
    let transaction: AccountTransaction?

    @State private var draft: TransactionDraft
    @State private var isAddingCategory = false
    @State private var newCategoryName = ""
    @State private var isConfirmingDelete = false
    @FocusState private var isAmountFocused: Bool

    init(account: Account, transaction: AccountTransaction? = nil) {
        self.account = account
        self.transaction = transaction
        _draft = State(initialValue: transaction.map(TransactionDraft.init(editing:)) ?? TransactionDraft(account: account))
    }

    private var otherAccounts: [Account] {
        AccountSort.name.sorted(accounts.filter { $0 !== account })
    }

    private var sortedCategories: [Category] {
        categories.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $draft.kind) {
                        ForEach(TransactionKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    LabeledContent("Amount") {
                        TextField("Amount", text: $draft.amountText, prompt: Text(Decimal.zero.formatted(.localCurrency)))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .amountKeyboard()
                            .focused($isAmountFocused)
                            // Shown as currency, but edited as a plain number so there's
                            // no symbol or grouping to type around.
                            .onChange(of: isAmountFocused) { _, isFocused in
                                guard let amount = draft.amount else { return }
                                draft.amountText = isFocused ? amount.editableText : amount.formatted(.localCurrency)
                            }
                    }

                    if draft.kind == .transfer {
                        transferAccountPicker
                    } else {
                        LabeledContent("Payee") {
                            TextField("Payee", text: $draft.payee, prompt: Text("Required"))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .capitalizesWords()
                        }
                    }

                    if draft.kind == .check {
                        LabeledContent("Check Number") {
                            TextField("Check Number", text: $draft.checkNumberText, prompt: Text("Optional"))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .numberKeyboard()
                        }
                    }

                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                    Toggle("Posted", isOn: $draft.isPosted)
                        .toggleStyle(.posted)
                } footer: {
                    footer
                }

                if draft.kind != .transfer {
                    Section {
                        Picker("Category", selection: $draft.category) {
                            Text("None").tag(Category?.none)
                            ForEach(sortedCategories) { category in
                                Text(category.name).tag(Optional(category))
                            }
                        }
                        Button("New Category…", systemImage: "plus") {
                            newCategoryName = ""
                            isAddingCategory = true
                        }
                    }
                }

                Section {
                    TextField("Note", text: $draft.note, prompt: Text("Note"), axis: .vertical)
                        .lineLimit(1 ... 4)
                }

                if transaction != nil {
                    Section {
                        Button("Delete Transaction", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                }
            }
            .sheetForm()
            .navigationTitle(transaction == nil ? "New Transaction" : "Edit Transaction")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!draft.isValid)
                }
            }
            .alert("New Category", isPresented: $isAddingCategory) {
                TextField("Name", text: $newCategoryName)
                    .capitalizesWords()
                Button("Cancel", role: .cancel) {}
                Button("Add", action: addCategory)
            }
            .confirmationDialog("Delete this transaction?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Transaction", role: .destructive, action: deleteTransaction)
            } message: {
                if let otherName = transaction?.transferCounterpart?.account?.name {
                    Text("The matching transfer in \(otherName) is deleted too.")
                }
            }
        }
    }

    @ViewBuilder
    private var transferAccountPicker: some View {
        if otherAccounts.isEmpty {
            LabeledContent(draft.isIncomingTransfer ? "From Account" : "To Account") {
                Text("No other accounts")
            }
        } else {
            Picker(draft.isIncomingTransfer ? "From Account" : "To Account", selection: $draft.otherAccount) {
                Text("Choose").tag(Account?.none)
                ForEach(otherAccounts) { other in
                    Text(other.name).tag(Optional(other))
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if draft.hasInvalidAmount {
            Text("Enter an amount above zero, such as 42.50.")
                .foregroundStyle(.red)
        } else if draft.kind == .check, draft.hasInvalidCheckNumber {
            Text("Enter a whole number for the check, or leave it blank.")
                .foregroundStyle(.red)
        } else if draft.kind == .transfer, otherAccounts.isEmpty {
            Text("Add another account to transfer money between accounts.")
        } else if let original = transaction, original.kind == .transfer, draft.kind != .transfer {
            Text("Saving removes the matching transfer from the other account.")
        }
    }

    private func addCategory() {
        if let category = try? Ledger.category(named: newCategoryName, in: modelContext) {
            draft.category = category
        }
    }

    private func save() {
        withAnimation {
            _ = Ledger.save(draft, in: account, editing: transaction, context: modelContext)
        }
        dismiss()
    }

    private func deleteTransaction() {
        guard let transaction else { return }
        withAnimation {
            Ledger.delete(transaction, in: modelContext)
        }
        dismiss()
    }
}

#Preview("New") {
    let container = ModelContainer.preview
    let checking = try! container.mainContext.fetch(
        FetchDescriptor<Account>(predicate: #Predicate { $0.name == "Checking" })
    ).first!
    return TransactionFormView(account: checking)
        .modelContainer(container)
}

#Preview("Edit Check") {
    let container = ModelContainer.preview
    let check = try! container.mainContext.fetch(
        FetchDescriptor<AccountTransaction>(predicate: #Predicate { $0.checkNumber != nil })
    ).first!
    return TransactionFormView(account: check.account!, transaction: check)
        .modelContainer(container)
}
