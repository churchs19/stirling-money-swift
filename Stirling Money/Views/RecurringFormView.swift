import SwiftData
import SwiftUI

/// Adds a recurring transaction or edits one: what to add, the schedule, and when it ends.
struct RecurringFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]
    @Query private var categories: [Category]

    /// The rule being edited, or nil for a new one.
    let rule: RecurringTransaction?
    /// For "Make Recurring…": the transaction the rule was made from, linked to it on saving.
    let madeFrom: AccountTransaction?

    @State private var draft: RecurringDraft
    @State private var isConfirmingDelete = false

    init(draft: RecurringDraft, rule: RecurringTransaction? = nil, madeFrom: AccountTransaction? = nil) {
        _draft = State(initialValue: draft)
        self.rule = rule
        self.madeFrom = madeFrom
        // Accounts and categories from the rule's book.
        let book = rule?.book ?? draft.account?.book
        _accounts = Query(filter: Account.inBook(book))
        _categories = Query(filter: Category.inBook(book))
    }

    /// Editing `rule`.
    init(editing rule: RecurringTransaction) {
        self.init(draft: RecurringDraft(editing: rule), rule: rule)
    }

    private var sortedAccounts: [Account] {
        AccountSort.name.sorted(accounts)
    }

    private var sortedCategories: [Category] {
        categories.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var unitName: String {
        switch draft.frequency {
        case .weekly: draft.interval == 1 ? String(localized: "week") : String(localized: "weeks")
        case .monthly, .twiceMonthly: draft.interval == 1 ? String(localized: "month") : String(localized: "months")
        case .yearly: draft.interval == 1 ? String(localized: "year") : String(localized: "years")
        }
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
                    .accessibilityIdentifier("recurringType")
                }

                Section {
                    CurrencyField("Amount", text: $draft.amountText, identifier: "recurringAmount")
                    Picker(draft.kind == .transfer ? "From Account" : "Account", selection: $draft.account) {
                        Text("Choose").tag(Account?.none)
                        ForEach(sortedAccounts) { account in
                            Text(account.name).tag(Optional(account))
                        }
                    }
                    .accessibilityIdentifier("recurringAccount")
                    if draft.kind == .transfer {
                        Picker("To Account", selection: $draft.otherAccount) {
                            Text("Choose").tag(Account?.none)
                            ForEach(sortedAccounts.filter { $0 !== draft.account }) { account in
                                Text(account.name).tag(Optional(account))
                            }
                        }
                        .accessibilityIdentifier("recurringOtherAccount")
                    } else {
                        LabeledContent("Payee") {
                            TextField("Payee", text: $draft.payee, prompt: Text("Required"))
                                .accessibilityIdentifier("recurringPayee")
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .capitalizesWords()
                        }
                        Picker("Category", selection: $draft.category) {
                            Text("None").tag(Category?.none)
                            ForEach(sortedCategories) { category in
                                Text(category.name).tag(Optional(category))
                            }
                        }
                    }
                } footer: {
                    if draft.hasInvalidAmount {
                        Text("Enter an amount above zero, such as 42.50.")
                            .foregroundStyle(.red)
                    } else if draft.kind == .check {
                        Text("Each check gets the account's next check number when it's added.")
                    }
                }

                Section {
                    Picker("Repeats", selection: $draft.frequency) {
                        ForEach(RecurrenceFrequency.allCases) { frequency in
                            Text(frequency.title).tag(frequency)
                        }
                    }
                    .accessibilityIdentifier("recurringFrequency")
                    if draft.frequency != .twiceMonthly {
                        Stepper(value: $draft.interval, in: 1 ... 99) {
                            Text("Every \(draft.interval) \(unitName)")
                        }
                    }
                    DatePicker("Starts", selection: $draft.startDate, displayedComponents: .date)
                    if draft.frequency == .twiceMonthly {
                        Picker("And on the", selection: $draft.secondDay) {
                            ForEach(1 ... 31, id: \.self) { day in
                                Text(day.formatted(.number)).tag(day)
                            }
                        }
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    scheduleFooter
                }

                Section("Ends") {
                    Picker("Ends", selection: $draft.end) {
                        ForEach(RecurringEnd.allCases) { end in
                            Text(end.title).tag(end)
                        }
                    }
                    .labelsHidden()
                    switch draft.end {
                    case .never:
                        EmptyView()
                    case .onDate:
                        DatePicker("Last Date", selection: $draft.endDate, displayedComponents: .date)
                    case .afterCount:
                        LabeledContent(rule == nil ? "Times" : "Times Left") {
                            TextField("Times", text: $draft.countText, prompt: Text("12"))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .numberKeyboard()
                        }
                    }
                }

                Section {
                    TextField("Note", text: $draft.note, prompt: Text("Note"), axis: .vertical)
                        .lineLimit(1 ... 4)
                }

                if rule != nil {
                    Section {
                        Button("Delete Recurring Transaction", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                }
            }
            .sheetForm()
            .navigationTitle(rule == nil ? "New Recurring" : "Edit Recurring")
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
            .confirmationDialog("Delete this recurring transaction?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Recurring Transaction", role: .destructive, action: deleteRule)
            } message: {
                Text("Transactions it already added stay in the register.")
            }
        }
    }

    @ViewBuilder
    private var scheduleFooter: some View {
        if draft.hasSameDayTwice() {
            Text("Choose a different day from the start date's.")
                .foregroundStyle(.red)
        } else if draft.endsBeforeStart() {
            Text("The last date is before the start.")
                .foregroundStyle(.red)
        } else if draft.hasInvalidCount {
            Text("Enter a whole number of times, such as 12.")
                .foregroundStyle(.red)
        } else {
            let dates = draft.upcomingDates().map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
            if let first = dates.first {
                if dates.count > 1 {
                    Text("Next: \(first); then \(dates.dropFirst().joined(separator: ", ")).")
                } else {
                    Text("Next: \(first).")
                }
            }
        }
    }

    private func save() {
        withAnimation {
            if let saved = draft.save(in: modelContext, editing: rule), let madeFrom {
                madeFrom.recurrence = saved
                madeFrom.transferCounterpart?.recurrence = saved
            }
        }
        // Anything already due (a start today or earlier) is added straight away.
        RecurringRunner.run()
        dismiss()
    }

    private func deleteRule() {
        guard let rule else { return }
        withAnimation {
            modelContext.delete(rule)
        }
        dismiss()
    }
}

#Preview("New") {
    let container = ModelContainer.preview
    let checking = try! container.mainContext.fetch(
        FetchDescriptor<Account>(predicate: #Predicate { $0.name == "Checking" })
    ).first!
    return RecurringFormView(draft: RecurringDraft(account: checking))
        .modelContainer(container)
}

#Preview("Edit") {
    let container = ModelContainer.preview
    let rule = try! container.mainContext.fetch(FetchDescriptor<RecurringTransaction>()).first!
    return RecurringFormView(editing: rule)
        .modelContainer(container)
}
