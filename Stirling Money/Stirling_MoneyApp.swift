import SwiftData
import SwiftUI

@main
struct Stirling_MoneyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appLock = AppLock()

    /// Whether the app was launched only to host the unit tests. Then it uses an empty in-memory store and
    /// doesn't write the widget summary or talk to the Watch, so tests never touch the real data. (UI tests launch
    /// the app as a separate process without this variable, so they get the normal app.)
    nonisolated static var isHostingUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var sharedModelContainer: ModelContainer = {
        if Self.isHostingUnitTests {
            do {
                return try ModelContainer(
                    for: Schema(AppSchema.models),
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } catch {
                fatalError("Could not create the in-memory ModelContainer for tests: \(error)")
            }
        }

        #if DEBUG
            // Launch with `-UseSampleData` to review screens with the preview data in memory.
            // The real store on disk is left untouched.
            if ProcessInfo.processInfo.arguments.contains("-UseSampleData") {
                return .preview
            }
        #endif

        let schema = Schema(AppSchema.models)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        guard !Self.isHostingUnitTests else { return }
        #if os(iOS)
            // Before the writer starts, so its first summary can go straight to the Watch.
            WatchSync.start()
        #endif
        WidgetSnapshotWriter.startObserving(sharedModelContainer.mainContext)
    }

    /// The app's window: its tabs, covered by the lock screen while locked.
    private var content: some View {
        RootView()
            .overlay {
                if appLock.isLocked {
                    LockView()
                }
            }
            // Widget links go to a window that's already open instead of opening another one
            // (on the Mac, and on iPad with several windows). With no window open, one is created.
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            .appAccent()
    }

    var body: some Scene {
        WindowGroup {
            if Self.isHostingUnitTests {
                // Nothing to draw: the tests make their own models and views.
                Color.clear
            } else {
                content
            }
        }
        .modelContainer(sharedModelContainer)
        .environment(appLock)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                appLock.lockIfEnabled()
                WidgetSnapshotWriter.updateNow()
            case .active:
                Task { await appLock.promptIfNeeded() }
            default:
                break
            }
        }

        #if os(macOS)
            Settings {
                SettingsView()
                    .frame(minWidth: 420, minHeight: 380)
                    .appAccent()
            }
            .modelContainer(sharedModelContainer)
            .environment(appLock)
        #endif
    }
}
