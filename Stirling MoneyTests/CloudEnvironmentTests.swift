import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

/// Moving a device's sync from the CloudKit development environment to production (a TestFlight build over a
/// development one).
@MainActor
struct CloudEnvironmentTests {
    /// A provisioning profile as it's embedded: signature bytes around an XML property list.
    private func profile(entitlements: String) -> Data {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Name</key><string>Stirling Money</string>
        <key>Entitlements</key><dict>\(entitlements)</dict>
        </dict></plist>
        """
        return Data([0x30, 0x82, 0x01, 0x02]) + Data(plist.utf8) + Data([0x00, 0xA0, 0x82])
    }

    @Test func theProfileTellsTheEnvironment() {
        // iOS profiles, as Xcode makes them.
        let iOSDevelopment = profile(entitlements: "<key>aps-environment</key><string>development</string><key>get-task-allow</key><true/>")
        let iOSDistribution = profile(entitlements: "<key>aps-environment</key><string>production</string><key>get-task-allow</key><false/>")
        #expect(CloudEnvironment.environment(ofProfile: iOSDevelopment) == .development)
        #expect(CloudEnvironment.environment(ofProfile: iOSDistribution) == .production)
        // The Mac's development profile has no get-task-allow; its push key has another name.
        let macDevelopment = profile(entitlements: "<key>com.apple.developer.aps-environment</key><string>development</string>")
        let macDistribution = profile(entitlements: "<key>com.apple.developer.aps-environment</key><string>production</string>")
        #expect(CloudEnvironment.environment(ofProfile: macDevelopment) == .development)
        #expect(CloudEnvironment.environment(ofProfile: macDistribution) == .production)
        // Without a push entitlement, a debuggable profile is a development one.
        #expect(CloudEnvironment.environment(ofProfile: profile(entitlements: "<key>get-task-allow</key><true/>")) == .development)
        // An iOS build from TestFlight or the App Store has no profile.
        #expect(CloudEnvironment.environment(ofProfile: nil) == .production)
        #expect(CloudEnvironment.environment(ofProfile: Data("not a profile".utf8)) == .production)
    }

    @Test func movingIsOnlyForAChangedEnvironment() {
        #expect(CloudEnvironment.needsMigration(saved: .development, hasSyncedBefore: true, current: .production))
        #expect(!CloudEnvironment.needsMigration(saved: .production, hasSyncedBefore: true, current: .production))
        // Synced before the environment was noted: every earlier build was a development build.
        #expect(CloudEnvironment.needsMigration(saved: nil, hasSyncedBefore: true, current: .production))
        #expect(!CloudEnvironment.needsMigration(saved: nil, hasSyncedBefore: true, current: .development))
        // Never synced: nothing to move.
        #expect(!CloudEnvironment.needsMigration(saved: nil, hasSyncedBefore: false, current: .production))
    }

    @Test func twoDevicesMoveToProductionWithoutCopies() throws {
        let development = FakeServer()
        let phone = try Device()
        let mac = try Device()
        let home = Book(name: "Home")
        phone.context.insert(home)
        let checking = Account(name: "Checking", initialBalance: 100)
        phone.context.insert(checking)
        checking.book = home
        Ledger.addTransaction(.withdrawal, amount: 20, to: checking, payee: "Grocer", in: phone.context)
        let empty = Book(name: "Trip")
        phone.context.insert(empty)
        try phone.context.save()
        try phone.send(to: development)
        try mac.fetch(from: development)

        // The phone gets the TestFlight build first: everything of the user's goes up to the empty production
        // environment, the empty book too.
        let production = FakeServer()
        try phone.processor.forgetSyncState()
        _ = try phone.processor.localChanges()
        phone.queue(try phone.processor.unsentChanges())
        try phone.send(to: production)
        #expect(production.records(ofType: Book.recordType).count == 2)
        #expect(production.records(ofType: Account.recordType).count == 1)
        #expect(production.records(ofType: AccountTransaction.recordType).count == 1)

        // Then the Mac: it finds the same books by name, so nothing is doubled.
        try mac.processor.forgetSyncState()
        _ = try mac.processor.localChanges()
        try mac.fetch(from: production)
        mac.queue(try mac.processor.unsentChanges())
        try mac.send(to: production)
        #expect(production.records(ofType: Book.recordType).count == 2)
        #expect(production.records(ofType: AccountTransaction.recordType).count == 1)
        #expect(try mac.context.fetchCount(FetchDescriptor<Book>()) == 2)
        #expect(try mac.accounts().map(\.balance) == [80])
    }
}
