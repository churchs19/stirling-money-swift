import Foundation

/// The keys the iPhone app and the Watch app use with WatchConnectivity.
///
/// - The iPhone sends the latest summary (`WidgetSnapshot` as JSON) as its application context:
///   `[snapshotKey: Data]`. The system keeps only the newest one and hands it to the Watch app when it runs.
/// - The Watch asks for a fresh one with `sendMessage([requestKey: true])`; the iPhone replies with
///   `[snapshotKey: Data]`, or an empty dictionary if it hasn't written a summary yet.
nonisolated enum WatchMessage {
    static let snapshotKey = "snapshot"
    static let requestKey = "requestSnapshot"
}
