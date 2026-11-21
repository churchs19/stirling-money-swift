import StoreKit
import SwiftData
import SwiftUI
import WidgetKit

/// App settings. A sheet from the Accounts ⋯ menu on iPhone and iPad; the Settings window (⌘,) on the Mac.
struct SettingsView: View {
    @Environment(AppLock.self) private var appLock
    @Environment(\.requestReview) private var requestReview
    @AppStorage("accountSort") private var sort: AccountSort = .name
    @AppStorage(AppLock.enabledKey) private var requiresUnlock = false
    @AppStorage(AccentChoice.key, store: AccentChoice.store) private var accentChoice: AccentChoice = .standard
    @AppStorage(AccentChoice.customColorKey, store: AccentChoice.store) private var customAccent = ""
    @Environment(\.self) private var environment
    @Query(sort: Book.order) private var books: [Book]
    @AppStorage(Books.currentKey) private var currentBookID = ""

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
                .accessibilityIdentifier("sortAccounts")
            }

            Section {
                Picker("Accent Color", selection: $accentChoice) {
                    ForEach(AccentChoice.available) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .accessibilityIdentifier("accentChoice")
                if accentChoice == .custom {
                    ColorPicker("Custom Color", selection: customAccentBinding, supportsOpacity: false)
                        .accessibilityIdentifier("customAccent")
                }
            } header: {
                Text("Appearance")
            } footer: {
                switch accentChoice {
                case .standard:
                    Text("Stirling Money's purple.")
                case .system:
                    Text("The accent color chosen in System Settings → Appearance.")
                case .custom:
                    Text("A color you choose.")
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

            if let book = Books.current(id: currentBookID, in: books) {
                ExportSection(book: book, showsBookName: books.count > 1)
                    .id(book.syncID)
            }

            Section("About") {
                LabeledContent("Version", value: version)
                Button("Rate Stirling Money", systemImage: "star") {
                    requestReview()
                }
            }
        }
        .formStyle(.grouped)
        // The widgets read the accent color directly; the summary (for the Watch) carries it too.
        .onChange(of: accentChoice) {
            WidgetCenter.shared.reloadAllTimelines()
            WidgetSnapshotWriter.scheduleUpdate()
        }
        .onChange(of: customAccent) {
            WidgetCenter.shared.reloadAllTimelines()
            WidgetSnapshotWriter.scheduleUpdate()
        }
        .navigationTitle("Settings")
    }

    /// The custom accent color; it starts from the default until one is picked.
    private var customAccentBinding: Binding<Color> {
        Binding {
            AccentChoice.custom.color(customColor: customAccent)
        } set: { newColor in
            customAccent = AccentChoice.encode(newColor.resolve(in: environment))
        }
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

/// Exports the current book's transactions.
private struct ExportSection: View {
    @Query private var transactions: [AccountTransaction]
    let book: Book
    /// Whether to name the book, when there's more than one.
    let showsBookName: Bool

    init(book: Book, showsBookName: Bool) {
        self.book = book
        self.showsBookName = showsBookName
        _transactions = Query(filter: AccountTransaction.inBook(book))
    }

    var body: some View {
        Section {
            ShareLink(
                item: CSVExportFile(text: TransactionCSV.make(transactions), filename: filename),
                preview: SharePreview("Stirling Money Transactions", image: Image(systemName: "tablecells"))
            ) {
                Label("Export Transactions", systemImage: "square.and.arrow.up")
            }
            .disabled(transactions.isEmpty)
        } header: {
            Text("Data")
        } footer: {
            if showsBookName {
                Text("A CSV file of every transaction in \(book.name), for a spreadsheet or a backup.")
            } else {
                Text("A CSV file of every transaction, for a spreadsheet or a backup.")
            }
        }
    }

    private var filename: String {
        let date = Date.now.formatted(.iso8601.year().month().day())
        return showsBookName
            ? "Stirling Money \(book.name.replacing("/", with: "-")) \(date).csv"
            : "Stirling Money Transactions \(date).csv"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AppLock())
    .modelContainer(.preview)
}
