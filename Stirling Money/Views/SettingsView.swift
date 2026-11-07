import StoreKit
import SwiftData
import SwiftUI

/// App settings. A tab on iPhone and iPad; the Settings window (⌘,) on the Mac.
struct SettingsView: View {
    @Environment(AppLock.self) private var appLock
    @Environment(SyncMonitor.self) private var syncMonitor
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
                LabeledContent("iCloud Sync") {
                    Text(syncStatusText)
                }
                if let lastImport = syncMonitor.lastImport {
                    LabeledContent("Last Received") {
                        Text(lastImport, format: .relative(presentation: .named))
                    }
                }
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
                Text("\(syncFooterText) Export makes a CSV file of every transaction, for a spreadsheet or a backup.")
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

    private var syncStatusText: String {
        switch syncMonitor.status {
        case .off: String(localized: "Off")
        case .checking: String(localized: "Checking…")
        case .available: String(localized: "On")
        case .noAccount: String(localized: "Not Signed In")
        case .restricted: String(localized: "Restricted")
        case .unavailable: String(localized: "Unavailable")
        }
    }

    private var syncFooterText: String {
        switch syncMonitor.status {
        case .off:
            String(localized: "iCloud sync isn't set up in this version. Your data stays on this device.")
        case .checking, .available:
            String(localized: "Accounts, transactions, budgets and goals sync with your other devices through iCloud.")
        case .noAccount:
            String(localized: "Sign in to iCloud to sync with your other devices. Your data stays on this device until then.")
        case .restricted, .unavailable:
            String(localized: "iCloud isn't available right now. Your data stays on this device.")
        }
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
    .environment(SyncMonitor(context: ModelContainer.preview.mainContext, isCloudBacked: false))
    .modelContainer(.preview)
}
