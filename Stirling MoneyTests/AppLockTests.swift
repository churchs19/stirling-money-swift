import Foundation
import Testing
@testable import Stirling_Money

/// The Face ID / passcode lock (`AppLock`), with a stand-in for the system prompt.
@MainActor
struct AppLockTests {
    /// Stands in for Face ID: answers each prompt with the next result, and counts the prompts.
    final class FakeFaceID {
        var results: [Bool]
        private(set) var prompts: [String] = []

        init(_ results: [Bool]) {
            self.results = results
        }

        func ask(_ reason: String) async -> Bool {
            prompts.append(reason)
            return results.isEmpty ? false : results.removeFirst()
        }
    }

    /// A settings store of its own, so tests don't touch the app's.
    private func defaults(lockOn: Bool) -> UserDefaults {
        let suite = "AppLockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(lockOn, forKey: AppLock.enabledKey)
        return defaults
    }

    private func lock(on: Bool, faceID: FakeFaceID, hasPasscode: Bool = true) -> AppLock {
        AppLock(defaults: defaults(lockOn: on), canAuthenticate: { hasPasscode }, authenticator: faceID.ask)
    }

    @Test func startsLockedOnlyWhenTheLockIsOn() {
        #expect(lock(on: true, faceID: FakeFaceID([])).isLocked)
        #expect(!lock(on: false, faceID: FakeFaceID([])).isLocked)
    }

    @Test func goingToTheBackgroundLocksOnlyWhenTheLockIsOn() async {
        let on = lock(on: true, faceID: FakeFaceID([true]))
        await on.promptIfNeeded()
        #expect(!on.isLocked)
        on.lockIfEnabled()
        #expect(on.isLocked)

        let off = lock(on: false, faceID: FakeFaceID([]))
        off.lockIfEnabled()
        #expect(!off.isLocked)
    }

    @Test func readsTheSettingFromItsOwnStore() {
        // It used to read UserDefaults.standard here, whatever store it was given.
        let store = defaults(lockOn: false)
        let appLock = AppLock(defaults: store, canAuthenticate: { true }, authenticator: FakeFaceID([]).ask)
        #expect(!appLock.isEnabled)
        store.set(true, forKey: AppLock.enabledKey)
        #expect(appLock.isEnabled)
        appLock.lockIfEnabled()
        #expect(appLock.isLocked)
    }

    @Test func promptsOncePerLock() async {
        let faceID = FakeFaceID([true, true])
        let appLock = lock(on: true, faceID: faceID)
        await appLock.promptIfNeeded()
        #expect(!appLock.isLocked)
        // Becoming active again while unlocked doesn't ask.
        await appLock.promptIfNeeded()
        #expect(faceID.prompts.count == 1)

        appLock.lockIfEnabled()
        await appLock.promptIfNeeded()
        #expect(faceID.prompts.count == 2)
        #expect(!appLock.isLocked)
    }

    @Test func cancellingStaysLockedWithoutAskingAgainUntilUnlockIsTapped() async {
        let faceID = FakeFaceID([false, true])
        let appLock = lock(on: true, faceID: faceID)
        await appLock.promptIfNeeded()
        #expect(appLock.isLocked)

        // The system prompt makes the app inactive and active again; asking again then would loop.
        await appLock.promptIfNeeded()
        #expect(faceID.prompts.count == 1)

        // Tapping Unlock asks again.
        await appLock.unlock()
        #expect(faceID.prompts.count == 2)
        #expect(!appLock.isLocked)
    }

    @Test func withoutAPasscodeItUnlocksRatherThanShuttingYouOut() async {
        let faceID = FakeFaceID([])
        let appLock = lock(on: true, faceID: faceID, hasPasscode: false)
        await appLock.promptIfNeeded()
        #expect(!appLock.isLocked)
        #expect(faceID.prompts.isEmpty)
    }

    @Test func unlockingWhileUnlockedDoesNothing() async {
        let faceID = FakeFaceID([true])
        let appLock = lock(on: false, faceID: faceID)
        await appLock.unlock()
        #expect(faceID.prompts.isEmpty)
    }

    @Test func aSecondUnlockWhileOneIsAskingDoesNothing() async {
        // A prompt that waits until the test answers it.
        var answer: CheckedContinuation<Bool, Never>?
        var prompts = 0
        let appLock = AppLock(defaults: defaults(lockOn: true), canAuthenticate: { true }) { _ in
            prompts += 1
            return await withCheckedContinuation { answer = $0 }
        }

        let first = Task { await appLock.unlock() }
        while answer == nil {
            await Task.yield()
        }
        #expect(appLock.isAuthenticating)

        await appLock.unlock()
        #expect(prompts == 1, "the second tap doesn't open another prompt")

        answer?.resume(returning: true)
        await first.value
        #expect(!appLock.isAuthenticating)
        #expect(!appLock.isLocked)
    }

    @Test func authenticatePassesTheReasonAndReportsTheResult() async {
        let faceID = FakeFaceID([false])
        let appLock = lock(on: false, faceID: faceID)
        #expect(await !appLock.authenticate(reason: "Confirm it's you"))
        #expect(faceID.prompts == ["Confirm it's you"])
        #expect(!appLock.isAuthenticating)
    }
}
