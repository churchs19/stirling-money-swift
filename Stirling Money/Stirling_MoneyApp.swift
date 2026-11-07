import SwiftData
import SwiftUI

@main
struct Stirling_MoneyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appLock = AppLock()

    var sharedModelContainer: ModelContainer = {
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
        WidgetSnapshotWriter.startObserving(sharedModelContainer.mainContext)
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
            }
            .modelContainer(sharedModelContainer)
            .environment(appLock)
        #endif
    }
}
