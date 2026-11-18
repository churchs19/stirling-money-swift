import Foundation

/// How the app was launched: normally, to host the unit tests, or for the UI tests.
nonisolated enum LaunchMode {
    /// Launched only to host the unit tests: an empty in-memory store, no screens, and no widget summary or Watch,
    /// so tests never touch the real data. (UI tests launch the app as a separate process without this variable.)
    static var isHostingUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Launched by the UI tests with `-UITesting` (Debug builds only): the sample data in memory, settings in a store
    /// of their own that starts empty (so the lock is off and the accent, layout and sort are the defaults), and no
    /// widget summary or Watch.
    static var isUITesting: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("-UITesting")
        #else
            false
        #endif
    }

    /// Whether to leave the widget summary and the Watch alone.
    static var isTesting: Bool {
        isHostingUnitTests || isUITesting
    }

    static let uiTestingSuite = "net.s-church.stirlingmoney.uitesting"

    /// Where settings are kept: the standard store, or under UI tests a store of their own, emptied at launch.
    @MainActor static let settings: UserDefaults = {
        guard isUITesting, let store = UserDefaults(suiteName: uiTestingSuite) else { return .standard }
        store.removePersistentDomain(forName: uiTestingSuite)
        return store
    }()
}
