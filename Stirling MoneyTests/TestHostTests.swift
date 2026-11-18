import Testing
@testable import Stirling_Money

/// Checks that the app hosting these tests stays out of the way.
struct TestHostTests {
    @Test func appKnowsItIsHostingUnitTests() {
        // Otherwise the host app opens the real store, rewrites the widget summary and talks to the Watch.
        #expect(LaunchMode.isHostingUnitTests)
        #expect(LaunchMode.isTesting)
        #expect(!LaunchMode.isUITesting, "only the UI tests pass -UITesting")
    }
}
