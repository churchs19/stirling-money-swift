import SwiftUI

@main
struct StirlingMoneyWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = Self.usesSampleData ? WatchStore(fileURL: nil, snapshot: .sample) : WatchStore()

    /// Launched with `-UseSampleData` (Debug builds only, as the UI tests do): show `WidgetSnapshot.sample` and leave
    /// the iPhone and the saved summary alone.
    private static var usesSampleData: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("-UseSampleData")
        #else
            false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task {
                    guard !Self.usesSampleData else { return }
                    store.start()
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Ask the iPhone for a fresh summary each time the app comes to the front.
                    guard phase == .active else { return }
                    store.showToday()
                    if !Self.usesSampleData {
                        store.refresh()
                    }
                }
        }
    }
}
