import StoreKit
import SwiftData
import SwiftUI

/// App settings. A tab on iPhone and iPad; the Settings window (⌘,) on the Mac.
struct SettingsView: View {
    @Environment(AppLock.self) private var appLock
    @Environment(\.requestReview) private var requestReview
    @AppStorage("accountSort") private var sort: AccountSort = .name
    @AppStorage(AppLock.enabledKey) private var requiresUnlock = false
    @Query private var transactions: [AccountTransaction]

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section("Accounts") {
                Picker("Sort Accounts By", selection: $sort) {
                    ForEach(AccountSort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }

            Section {
                Toggle("Require \(AppLock.methodName)", isOn: lockBinding)
                    .disabled(!AppLock.isAvailable)
            } header: {
                Text("Privacy")
            } footer: {
                if AppLock.isAvailable {
                    Text("Asks for \(AppLock.methodName) when the app opens and when you come back to it.")
                } else {
                    Text("Set a passcode on this device to lock the app.")
                }
            }

            Section {
                ShareLink(
                    item: CSVExportFile(text: TransactionCSV.make(transactions), filename: exportFilename),
                    preview: SharePreview("Stirling Money Transactions", image: Image(systemName: "tablecells"))
                ) {
                    Label("Export Transactions", systemImage: "square.and.arrow.up")
                }
                .disabled(transactions.isEmpty)
            } header: {
                Text("Data")
            } footer: {
                Text("A CSV file of every transaction, for a spreadsheet or a backup.")
            }

            Section("About") {
                LabeledContent("Version", value: version)
                Button("Rate Stirling Money", systemImage: "star") {
                    requestReview()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private var exportFilename: String {
        "Stirling Money Transactions \(Date.now.formatted(.iso8601.year().month().day())).csv"
    }

    /// Turning the lock on asks for Face ID first, so it's known to work before the app relies on it.
    private var lockBinding: Binding<Bool> {
        Binding {
            requiresUnlock
        } set: { newValue in
            guard newValue else {
                requiresUnlock = false
                return
            }
            Task {
                if await appLock.authenticate(reason: String(localized: "Confirm it's you to turn on the lock.")) {
                    requiresUnlock = true
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AppLock())
    .modelContainer(.preview)
}
