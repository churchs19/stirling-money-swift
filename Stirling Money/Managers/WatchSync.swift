#if os(iOS)
    import Foundation
    import os
    import WatchConnectivity

    /// Sends the summary the widgets read (`WidgetSnapshot`) to the Apple Watch app.
    ///
    /// `WidgetSnapshotWriter` calls `send(_:)` whenever it writes a new summary. When the session first
    /// activates, the summary already on disk is sent, so a newly installed Watch app gets data without
    /// waiting for a change. When the Watch asks for a fresh summary, the reply is the file on disk
    /// (current as of the last save), and the app also brings the file up to date, which sends again if
    /// anything changed. Replying from the file means no hop to the main actor from the session's queue.
    ///
    /// iPhone only: WatchConnectivity doesn't exist on the Mac, and `isSupported` is false on iPad.
    final nonisolated class WatchSync: NSObject, WCSessionDelegate, Sendable {
        static let shared = WatchSync()

        private static let log = Logger(subsystem: "net.s-church.stirlingmoney", category: "WatchSync")

        /// Starts the session. Call once, at launch, before anything is sent: the iPhone app can be
        /// launched in the background just to answer the Watch.
        static func start() {
            guard WCSession.isSupported() else { return }
            let session = WCSession.default
            session.delegate = shared
            session.activate()
        }

        /// Sends `snapshot` (encoded `WidgetSnapshot`) as the application context, if there's a Watch to send it to.
        func send(_ snapshot: Data) {
            guard WCSession.isSupported() else { return }
            let session = WCSession.default
            guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
                Self.log.notice("Not sending to the Watch: activated \(session.activationState == .activated), paired \(session.isPaired), app installed \(session.isWatchAppInstalled)")
                return
            }
            do {
                try session.updateApplicationContext([WatchMessage.snapshotKey: snapshot])
                Self.log.notice("Sent a summary of \(snapshot.count) bytes to the Watch")
            } catch {
                Self.log.error("Couldn't send the summary to the Watch: \(error.localizedDescription)")
            }
        }

        /// The summary last written for the widgets, or nil if there isn't one yet.
        private static func savedSnapshot() -> Data? {
            guard let url = WidgetSnapshot.fileURL else { return nil }
            return try? Data(contentsOf: url)
        }

        // MARK: WCSessionDelegate

        func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
            if let error {
                Self.log.error("Watch session didn't activate: \(error.localizedDescription)")
                return
            }
            Self.log.notice("Watch session activated: paired \(session.isPaired), app installed \(session.isWatchAppInstalled)")
            if activationState == .activated, let snapshot = Self.savedSnapshot() {
                send(snapshot)
            }
        }

        func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
            Self.log.notice("The Watch asked for a summary")
            guard message[WatchMessage.requestKey] != nil else {
                replyHandler([:])
                return
            }
            if let snapshot = Self.savedSnapshot() {
                replyHandler([WatchMessage.snapshotKey: snapshot])
            } else {
                replyHandler([:])
            }
            // The file is as of the last save; refresh it too (budgets roll over, for example).
            // If the summary changes, the writer sends it as the new application context.
            Task { @MainActor in WidgetSnapshotWriter.updateNow() }
        }

        func sessionWatchStateDidChange(_ session: WCSession) {
            // A Watch app was just installed (or the Watch was paired): give it the current summary.
            if session.activationState == .activated, let snapshot = Self.savedSnapshot() {
                send(snapshot)
            }
        }

        func sessionDidBecomeInactive(_ session: WCSession) {}

        func sessionDidDeactivate(_ session: WCSession) {
            // Switching to another Watch: activate again for the new one.
            session.activate()
        }
    }
#endif
