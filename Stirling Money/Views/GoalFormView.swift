import SwiftData
import SwiftUI

/// Adds or edits a savings goal. Nothing changes until Save.
struct GoalFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]

    /// The goal being edited, or nil for a new one.
    let goal: Goal?

    @State private var draft: GoalDraft
    @State private var isConfirmingDelete = false

    init(goal: Goal? = nil) {
        self.goal = goal
        _draft = State(initialValue: goal.map(GoalDraft.init(editing:)) ?? GoalDraft())
    }

    private var sortedAccounts: [Account] {
        AccountSort.name.sorted(accounts)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Name") {
                        TextField("Name", text: $draft.name, prompt: Text("Required"))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .capitalizesWords()
                    }
                    CurrencyField("Target", text: $draft.targetText)
                    DatePicker("Target Date", selection: $draft.targetDate, displayedComponents: .date)
                } footer: {
                    if draft.hasInvalidTarget {
                        Text("Enter an amount above zero, such as 5000.")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Picker("Account", selection: $draft.account) {
                        Text("Choose").tag(Account?.none)
                        ForEach(sortedAccounts) { account in
                            Text(account.name).tag(Optional(account))
                        }
                    }
                } footer: {
                    if let footer = accountFooter {
                        Text(footer)
                    }
                }

                if goal != nil {
                    Section {
                        Button("Delete Goal", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                }
            }
            .sheetForm()
            .navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
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
            .confirmationDialog("Delete this goal?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Goal", role: .destructive, action: deleteGoal)
            } message: {
                Text("The account and its transactions aren't affected.")
            }
        }
    }

    /// Explains where progress is measured from.
    private var accountFooter: String? {
        guard let account = draft.account else {
            return String(localized: "The goal tracks this account's balance.")
        }
        let balance = account.balance.formatted(.localCurrency)
        if let goal, goal.account === account {
            let start = goal.initialBalance.formatted(.localCurrency)
            return String(localized: "Progress is measured from \(start), the balance when the goal started.")
        }
        return String(localized: "Progress is measured from the account's balance today, \(balance).")
    }

    private func save() {
        withAnimation {
            _ = draft.save(editing: goal, in: modelContext)
        }
        dismiss()
    }

    private func deleteGoal() {
        guard let goal else { return }
        withAnimation {
            modelContext.delete(goal)
        }
        dismiss()
    }
}

#Preview("New") {
    GoalFormView()
        .modelContainer(.preview)
}

#Preview("Edit") {
    let container = ModelContainer.preview
    let goal = try! container.mainContext.fetch(FetchDescriptor<Goal>()).first!
    return GoalFormView(goal: goal)
        .modelContainer(container)
}
