import SwiftData
import SwiftUI

@main
struct Stirling_MoneyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appLock = AppLock(defaults: LaunchMode.settings)

    var sharedModelContainer: ModelContainer = {
        if LaunchMode.isHostingUnitTests {
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
            // Launch with `-UseSampleData` to review screens with the preview data in memory, as the UI tests
            // (`-UITesting`) do. The real store on disk is left untouched.
            if ProcessInfo.processInfo.arguments.contains("-UseSampleData") || LaunchMode.isUITesting {
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
        guard !LaunchMode.isTesting else { return }
        #if os(iOS)
            // Before the writer starts, so its first summary can go straight to the Watch.
            WatchSync.start()
        #endif
        WidgetSnapshotWriter.startObserving(sharedModelContainer.mainContext)
        // After the writer, so the transactions it adds reach the widgets and the Watch.
        RecurringRunner.start(sharedModelContainer.mainContext)
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
            // Settings: the standard store, or a fresh one under UI tests.
            .defaultAppStorage(LaunchMode.settings)
    }

    var body: some Scene {
        WindowGroup {
            if LaunchMode.isHostingUnitTests {
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
                RecurringRunner.scheduleBackgroundRefresh()
            case .active:
                RecurringRunner.run()
                Task { await appLock.promptIfNeeded() }
            default:
                break
            }
        }
        #if os(iOS)
            // iOS wakes the app for this at or after the earliest due date (see RecurringRunner).
            .backgroundTask(.appRefresh(RecurringRunner.taskIdentifier)) {
                await RecurringRunner.runInBackground()
            }
        #endif

        #if os(macOS)
            Settings {
                SettingsView()
                    .frame(minWidth: 420, minHeight: 380)
                    .appAccent()
                    .defaultAppStorage(LaunchMode.settings)
            }
            .modelContainer(sharedModelContainer)
            .environment(appLock)
        #endif
    }
}
