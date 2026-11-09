import SwiftData
import SwiftUI

struct NewAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var balanceText = ""
    @State private var iconName: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case name, balance
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Empty text means a zero balance; otherwise the text must parse as a number.
    private var parsedBalance: Decimal? {
        Decimal(userInput: balanceText)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && parsedBalance != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Account Name", text: $name)
                        .capitalizesWords()
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .balance }
                }

                Section {
                    TextField("Initial Balance", text: $balanceText, prompt: Text("0.00"))
                        .amountKeyboard()
                        .focused($focusedField, equals: .balance)
                        .submitLabel(.done)
                        .onSubmit(save)
                } header: {
                    // macOS forms already show the field's title as its label.
                    #if !os(macOS)
                        Text("Initial Balance")
                    #endif
                } footer: {
                    if parsedBalance == nil {
                        Text("Enter a number, such as 1250.75 or -342.18.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Use a negative amount for money owed, such as a credit card balance.")
                    }
                }

                Section {
                    AccountIconPicker(iconName: $iconName)
                } header: {
                    Text("Icon")
                } footer: {
                    Text("Shown on the account's tile.")
                }
            }
            .sheetForm()
            .navigationTitle("New Account")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear { focusedField = .name }
        }
    }

    private func save() {
        guard canSave, let balance = parsedBalance else { return }
        modelContext.insert(Account(name: trimmedName, initialBalance: balance, iconName: iconName))
        dismiss()
    }
}

#Preview {
    NewAccountView()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
