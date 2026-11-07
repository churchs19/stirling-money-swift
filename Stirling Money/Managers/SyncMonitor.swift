import CloudKit
import CoreData
import Foundation
import Observation
import SwiftData

/// Watches iCloud sync: the account's status for Settings, and imports from other devices,
/// after which duplicate categories are merged and the widgets refreshed.
@Observable
final class SyncMonitor {
    static let containerIdentifier = "iCloud.net.s-church.stirlingmoney"

    /// Whether this build syncs with iCloud. Off until the project is signed with a paid Apple
    /// Developer Program team: free personal teams can't have the iCloud and push entitlements.
    /// To turn sync on, set this to true and add the entitlements back (see README → iCloud).
    /// Asking CloudKit for a container the app isn't entitled to can crash, so the two must match.
    static let isEnabled = false

    enum Status: Equatable {
        /// This build doesn't sync (see `isEnabled`).
        case off
        case checking
        /// Syncing with iCloud.
        case available
        /// Not signed in to iCloud, or iCloud Drive is off for this app; data stays on this device.
        case noAccount
        /// Restricted by parental controls or device management.
        case restricted
        /// iCloud is temporarily unavailable, or the app couldn't open the iCloud store.
        case unavailable
    }

    private(set) var status: Status = .checking
    /// Whether the store was opened with iCloud. False if it had to fall back to this device only.
    let isCloudBacked: Bool
    private(set) var lastImport: Date?

    private let context: ModelContext
    private var observers: [any NSObjectProtocol] = []

    init(context: ModelContext, isCloudBacked: Bool) {
        self.context = context
        self.isCloudBacked = isCloudBacked
        guard isCloudBacked else {
            status = Self.isEnabled ? .unavailable : .off
            return
        }
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
            ) { [weak self] notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                    event.type == .import, event.endDate != nil, event.succeeded
                else { return }
                MainActor.assumeIsolated { self?.didImport() }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    _ = Task { await self?.refreshStatus() }
                }
            }
        )
    }

    func refreshStatus() async {
        guard isCloudBacked else { return }
        do {
            let accountStatus = try await CKContainer(identifier: Self.containerIdentifier).accountStatus()
            status = switch accountStatus {
            case .available: .available
            case .noAccount: .noAccount
            case .restricted: .restricted
            default: .unavailable
            }
        } catch {
            status = .unavailable
        }
    }

    /// Changes from another device have arrived.
    private func didImport() {
        lastImport = .now
        _ = try? CategoryMerger.mergeDuplicates(in: context)
        WidgetSnapshotWriter.scheduleUpdate()
    }
}
