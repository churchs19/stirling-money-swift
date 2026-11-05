import SwiftData
import SwiftUI

struct NewAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var balanceText = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case name, balance
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Empty text means a zero balance; otherwise the text must parse as a number.
    private var parsedBalance: Decimal? {
        let text = balanceText.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            return 0
        }
        return try? Decimal(text, format: .number)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && parsedBalance != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Account Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .balance }
                }

                Section {
                    TextField("0.00", text: $balanceText)
                        .keyboardType(.numbersAndPunctuation)
                        .focused($focusedField, equals: .balance)
                        .submitLabel(.done)
                        .onSubmit(save)
                } header: {
                    Text("Initial Balance")
                } footer: {
                    if parsedBalance == nil {
                        Text("Enter a number, such as 1250.75 or -342.18.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Use a negative amount for money owed, such as a credit card balance.")
                    }
                }
            }
            .navigationTitle("New Account")
            .navigationBarTitleDisplayMode(.inline)
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
        modelContext.insert(Account(name: trimmedName, initialBalance: balance))
        dismiss()
    }
}

#Preview {
    NewAccountView()
        .modelContainer(for: Account.self, inMemory: true)
}
