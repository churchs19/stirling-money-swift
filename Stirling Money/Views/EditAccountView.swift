import SwiftData
import SwiftUI

/// Edits an account in place. Valid changes apply as you type; Done is disabled while the form is invalid.
struct EditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var account: Account

    /// The balance is edited as text so a half-typed or invalid number doesn't overwrite the model.
    @State private var balanceText: String

    init(account: Account) {
        self.account = account
        _balanceText = State(initialValue: account.initialBalance.editableText)
    }

    private var trimmedName: String {
        account.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
                    TextField("Account Name", text: $account.name)
                        .capitalizesWords()
                } footer: {
                    if trimmedName.isEmpty {
                        Text("Enter a name for the account.")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    TextField("Initial Balance", text: $balanceText, prompt: Text("0.00"))
                        .amountKeyboard()
                        .onChange(of: balanceText) {
                            if let parsedBalance {
                                account.initialBalance = parsedBalance
                            }
                        }
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
                        Text("The balance before any transactions in this app. Use a negative amount for money owed.")
                    }
                }
            }
            .sheetForm()
            .navigationTitle("Edit Account")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        account.name = trimmedName
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(!canSave)
        }
    }
}

#Preview {
    let container = ModelContainer.preview
    let account = try! container.mainContext.fetch(FetchDescriptor<Account>()).first!
    return EditAccountView(account: account)
        .modelContainer(container)
}
