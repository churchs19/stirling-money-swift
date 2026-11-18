import Foundation
import LocalAuthentication
import Observation

/// Locks the app behind Face ID, Touch ID or the device passcode.
///
/// When "Require Face ID" is on in Settings, the app starts locked and locks again whenever it goes
/// to the background. Unlocking asks once when the app becomes active; after a cancel, the person taps
/// Unlock to try again (asking automatically would loop, since the system prompt itself deactivates the app).
@Observable
final class AppLock {
    static let enabledKey = "requiresUnlock"

    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    /// Set when the app locks, so it asks to unlock once the next time it's active.
    private var needsPrompt: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let canAuthenticate: () -> Bool
    @ObservationIgnored private let authenticator: (String) async -> Bool

    /// - Parameters:
    ///   - defaults: where the "Require Face ID" setting is stored.
    ///   - canAuthenticate: whether the device has Face ID, Touch ID or a passcode set up. Tests pass their own.
    ///   - authenticator: asks for Face ID, Touch ID or the passcode with the given reason, and returns whether it
    ///     succeeded. Tests pass their own.
    init(
        defaults: UserDefaults = .standard,
        canAuthenticate: @escaping () -> Bool = { AppLock.isAvailable },
        authenticator: @escaping (String) async -> Bool = AppLock.askDeviceOwner
    ) {
        self.defaults = defaults
        self.canAuthenticate = canAuthenticate
        self.authenticator = authenticator
        let enabled = defaults.bool(forKey: Self.enabledKey)
        isLocked = enabled
        needsPrompt = enabled
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    /// Call when the app goes to the background.
    func lockIfEnabled() {
        guard isEnabled else { return }
        isLocked = true
        needsPrompt = true
    }

    /// Call when the app becomes active or the lock screen appears.
    func promptIfNeeded() async {
        guard isLocked, needsPrompt else { return }
        needsPrompt = false
        await unlock()
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        // If the device no longer has a passcode, the lock can't be checked, so don't shut the person out.
        guard canAuthenticate() else {
            isLocked = false
            return
        }
        if await authenticate(reason: String(localized: "Unlock your accounts.")) {
            isLocked = false
        }
    }

    /// Asks for Face ID, Touch ID or the passcode. Returns whether it succeeded.
    func authenticate(reason: String) async -> Bool {
        isAuthenticating = true
        defer { isAuthenticating = false }
        return await authenticator(reason)
    }

    /// The real check: Face ID, Touch ID, Optic ID or the device passcode.
    static func askDeviceOwner(reason: String) async -> Bool {
        do {
            return try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }

    /// Whether the device has Face ID, Touch ID, Optic ID or at least a passcode set up.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// "Face ID", "Touch ID", "Optic ID" or "Passcode", for labels.
    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return String(localized: "Face ID")
        case .touchID: return String(localized: "Touch ID")
        case .opticID: return String(localized: "Optic ID")
        default: return String(localized: "Passcode")
        }
    }
}
