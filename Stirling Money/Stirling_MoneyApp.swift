import SwiftData
import SwiftUI

@main
struct Stirling_MoneyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    // Receives invitations to shared books (AppDelegate.swift).
    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #else
        @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var appLock = AppLock(defaults: LaunchMode.settings)

    var sharedModelContainer: ModelContainer = {
        if LaunchMode.isHostingUnitTests {
            do {
                return try ModelContainer(
                    for: Schema(AppSchema.models),
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                )
            } catch {
                fatalError("Could not create the in-memory ModelContainer for tests: \(error)")
            }
        }

        #if DEBUG
            // Launch with `-UseSampleData` to review screens with the preview data in memory, as the UI tests
            // (`-UITesting`) do. The real store on disk is left untouched.
            if LaunchMode.usesSampleData || LaunchMode.isUITesting {
                return .preview
            }
        #endif

        let schema = Schema(AppSchema.models)
        // `.none`: SyncCoordinator syncs the store. With the default (`.automatic`), SwiftData would also mirror it to
        // the app's iCloud container by itself, which has no shared database and would clash with ours.
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        guard !LaunchMode.isHostingUnitTests else { return }
        // Before anything reads the data: data from before books goes into the first book. If this fails, the
        // next launch tries again (and RootView makes a book if there's none).
        _ = try? Books.prepare(in: sharedModelContainer.mainContext)
        guard !LaunchMode.isTesting else { return }
        #if os(iOS)
            // Before the writer starts, so its first summary can go straight to the Watch.
            WatchSync.start()
        #endif
        WidgetSnapshotWriter.startObserving(sharedModelContainer.mainContext)
        // iCloud sync, once the app has the capability (SyncCoordinator.isEnabled).
        SyncCoordinator.start(sharedModelContainer.mainContext)
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
                SyncCoordinator.shared?.appResignedActive()
                appLock.lockIfEnabled()
                WidgetSnapshotWriter.updateNow()
                RecurringRunner.scheduleBackgroundRefresh()
            case .active:
                SyncCoordinator.shared?.appBecameActive()
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
