import CloudKit
import Foundation
import Observation

/// What Settings shows about iCloud sync: the account, when it last synced, the last problem, and whether the
/// user's own books are waiting for a choice after a different Apple ID signed in.
@MainActor
@Observable
final class SyncStatus {
    /// The iCloud account's state; nil until it's been checked.
    var account: CKAccountStatus?
    /// When a fetch or send last finished.
    var lastSynced: Date?
    /// The last thing that went wrong, for Settings; cleared by the next sync that works.
    var lastError: String?
    var isSyncing = false
    /// A different Apple ID signed in: the user's own books stay on this device, unsent, until they choose to upload
    /// them to it or remove them (Settings).
    var ownBooksAwaitChoice = false

    /// A long sync the user should know about, shown over the app (`SyncActivityOverlay`); nil the rest of the time.
    var activity: Activity?

    enum Activity: Equatable {
        /// The first sync on this device: books already in iCloud are on their way.
        case firstSync
        /// Accepting an invitation and fetching the book, named if the share says.
        case joining(bookName: String?)
    }

    /// A short description of the account's state.
    var accountText: String {
        switch account {
        case .available: String(localized: "On")
        case .noAccount: String(localized: "Not signed in")
        case .restricted: String(localized: "Restricted")
        case .temporarilyUnavailable: String(localized: "Temporarily unavailable")
        case .couldNotDetermine, nil: String(localized: "Checking…")
        @unknown default: String(localized: "Unknown")
        }
    }

    var canSync: Bool {
        account == .available && !isSyncing
    }
}
