import SwiftData
import SwiftUI

/// Adds or edits a budget. Nothing changes until Save.
struct BudgetFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [Category]

    /// The budget being edited, or nil for a new one.
    let budget: Budget?

    @State private var draft: BudgetDraft
    @State private var isConfirmingDelete = false

    init(budget: Budget? = nil) {
        self.budget = budget
        _draft = State(initialValue: budget.map { BudgetDraft(editing: $0) } ?? BudgetDraft())
    }

    private var sortedCategories: [Category] {
        categories.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Name") {
                        TextField("Name", text: $draft.name, prompt: Text("Required"))
                            .accessibilityIdentifier("budgetName")
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .capitalizesWords()
                    }
                    CurrencyField("Amount", text: $draft.amountText, identifier: "budgetAmount")
                    Picker("Category", selection: $draft.category) {
                        Text("All Spending").tag(Category?.none)
                        ForEach(sortedCategories) { category in
                            Text(category.name).tag(Optional(category))
                        }
                    }
                } footer: {
                    if draft.hasInvalidAmount {
                        Text("Enter an amount above zero, such as 400.")
                            .foregroundStyle(.red)
                    } else if draft.category == nil {
                        Text("Counts money going out of every account. Transfers don't count.")
                    } else {
                        Text("Counts this category's spending, less refunds. Transfers don't count.")
                    }
                }

                Section {
                    Picker("Period", selection: $draft.period) {
                        ForEach(BudgetPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    DatePicker("Start Date", selection: $draft.startDate, displayedComponents: .date)
                    if draft.period != .custom {
                        Toggle("Ends", isOn: $draft.hasEndDate.animation())
                    }
                    if draft.effectiveEndDate != nil {
                        DatePicker("End Date", selection: $draft.endDate, displayedComponents: .date)
                    }
                } footer: {
                    if draft.hasEndBeforeStart() {
                        Text("The end date must be on or after the start date.")
                            .foregroundStyle(.red)
                    } else {
                        Text(periodDescription)
                    }
                }

                if budget != nil {
                    Section {
                        Button("Delete Budget", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                }
            }
            .sheetForm()
            .navigationTitle(budget == nil ? "New Budget" : "Edit Budget")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("save")
                        .disabled(!draft.isValid)
                }
            }
            .confirmationDialog("Delete this budget?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Budget", role: .destructive, action: deleteBudget)
            } message: {
                Text("Transactions aren't affected.")
            }
        }
    }

    private var periodDescription: String {
        switch draft.period {
        case .weekly: String(localized: "Starts over every 7 days from the start date.")
        case .monthly: String(localized: "Starts over each month on the start date's day.")
        case .yearly: String(localized: "Starts over each year on the start date.")
        case .custom: String(localized: "One period from the start date through the end date.")
        }
    }

    private func save() {
        withAnimation {
            _ = draft.save(editing: budget, in: modelContext)
        }
        dismiss()
    }

    private func deleteBudget() {
        guard let budget else { return }
        withAnimation {
            modelContext.delete(budget)
        }
        dismiss()
    }
}

#Preview("New") {
    BudgetFormView()
        .modelContainer(.preview)
}

#Preview("Edit") {
    let container = ModelContainer.preview
    let budget = try! container.mainContext.fetch(FetchDescriptor<Budget>()).first!
    return BudgetFormView(budget: budget)
        .modelContainer(container)
}
