import SwiftUI

@main
struct StirlingMoneyWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task { store.start() }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Ask the iPhone for a fresh summary each time the app comes to the front.
                    if phase == .active {
                        store.refresh()
                    }
                }
        }
    }
}
