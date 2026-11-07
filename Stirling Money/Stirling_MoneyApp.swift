import SwiftData
import SwiftUI

@main
struct Stirling_MoneyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appLock = AppLock()

    @State private var syncMonitor: SyncMonitor
    private let sharedModelContainer: ModelContainer

    init() {
        let (container, isCloudBacked) = Self.makeContainer()
        sharedModelContainer = container
        _syncMonitor = State(initialValue: SyncMonitor(context: container.mainContext, isCloudBacked: isCloudBacked))
        WidgetSnapshotWriter.startObserving(container.mainContext)
    }

    /// The data store, synced with the private iCloud database when possible.
    /// Returns whether it's iCloud-backed. If CloudKit can't be set up (for example, the build's
    /// provisioning profile lacks the iCloud container), the same store opens on this device only.
    private static func makeContainer() -> (ModelContainer, isCloudBacked: Bool) {
        #if DEBUG
            // Launch with `-UseSampleData` to review screens with the preview data in memory.
            // The real store on disk is left untouched, and nothing syncs.
            if ProcessInfo.processInfo.arguments.contains("-UseSampleData") {
                return (.preview, false)
            }
        #endif

        let schema = Schema(AppSchema.models)
        if SyncMonitor.isEnabled {
            do {
                let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .private(SyncMonitor.containerIdentifier))
                return try (ModelContainer(for: schema, configurations: [cloud]), true)
            } catch {
                print("iCloud sync unavailable, using this device's store only: \(error)")
            }
        }
        do {
            let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            return try (ModelContainer(for: schema, configurations: [local]), false)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .overlay {
                    if appLock.isLocked {
                        LockView()
                    }
                }
                // Widget links go to a window that's already open instead of opening another one
                // (on the Mac, and on iPad with several windows). With no window open, one is created.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .task {
                    // Duplicates can also arrive while the app isn't running.
                    _ = try? CategoryMerger.mergeDuplicates(in: sharedModelContainer.mainContext)
                    await syncMonitor.refreshStatus()
                }
        }
        .modelContainer(sharedModelContainer)
        .environment(appLock)
        .environment(syncMonitor)
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
            }
            .modelContainer(sharedModelContainer)
            .environment(appLock)
            .environment(syncMonitor)
        #endif
    }
}
