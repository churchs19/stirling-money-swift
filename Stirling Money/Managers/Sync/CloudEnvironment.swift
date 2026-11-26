import Foundation

/// Which CloudKit environment this build syncs with. Development builds (run from Xcode) use the development
/// environment; TestFlight, App Store and ad hoc builds use production. Each has its own data.
///
/// Moving a device from one to the other (installing a TestFlight build over a development one) would otherwise
/// leave sync believing records exist that the new environment has never seen, so `SyncCoordinator` notes the
/// environment it synced with and starts over when it changes (`needsMigration`).
nonisolated enum CloudEnvironment: String, Codable {
    case development
    case production

    /// The environment of the running build, from its provisioning profile.
    static let current: CloudEnvironment = {
        #if targetEnvironment(simulator)
            // Simulator builds aren't provisioned and always use development.
            return .development
        #else
            return environment(ofProfile: embeddedProfile())
        #endif
    }()

    /// The profile's push environment says it (`aps-environment` on iOS, `com.apple.developer.aps-environment` on
    /// the Mac): `development` for a development profile, `production` for a distribution one. Failing that, a
    /// development profile allows a debugger (`get-task-allow`). An iOS build from TestFlight or the App Store has
    /// no profile at all.
    static func environment(ofProfile profile: Data?) -> CloudEnvironment {
        guard let profile, let entitlements = entitlements(inProfile: profile) else { return .production }
        if let push = (entitlements["aps-environment"] ?? entitlements["com.apple.developer.aps-environment"]) as? String {
            return push == "development" ? .development : .production
        }
        let debuggable = (entitlements["get-task-allow"] ?? entitlements["com.apple.security.get-task-allow"]) as? Bool
        return debuggable == true ? .development : .production
    }

    /// The `Entitlements` dictionary of a provisioning profile: a signed (CMS) wrapper around an XML property list.
    static func entitlements(inProfile data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound ..< data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data.subdata(in: start.lowerBound ..< end.upperBound), format: nil
              ) as? [String: Any]
        else { return nil }
        return plist["Entitlements"] as? [String: Any]
    }

    private static func embeddedProfile() -> Data? {
        #if os(macOS)
            let url = Bundle.main.bundleURL.appending(path: "Contents/embedded.provisionprofile")
        #else
            let url = Bundle.main.bundleURL.appending(path: "embedded.mobileprovision")
        #endif
        return try? Data(contentsOf: url)
    }

    /// Whether sync has to start over because this build uses a different environment than the last sync did.
    ///
    /// - Parameters:
    ///   - saved: the environment noted at the last sync, if any.
    ///   - hasSyncedBefore: whether this device has synced at all. Builds before the environment was noted were
    ///     all development builds, so a device that synced without noting it synced with development.
    static func needsMigration(saved: CloudEnvironment?, hasSyncedBefore: Bool, current: CloudEnvironment) -> Bool {
        guard let previous = saved ?? (hasSyncedBefore ? .development : nil) else { return false }
        return previous != current
    }
}
