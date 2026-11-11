import Foundation
import Observation
import SwiftUI
import os
import WatchConnectivity
import WidgetKit

/// The Watch's copy of the summary the iPhone sends (`WidgetSnapshot`).
///
/// - Loads the last summary from the App Group folder at launch, so the app and the complications have
///   something to show straight away.
/// - Receives new summaries as the iPhone's application context (delivered when the app runs, even if
///   the iPhone sent it while the app was closed) or as the reply to `refresh()`.
/// - Keeps only a summary newer than the one it has, saves it to the App Group folder for the
///   complications, and reloads their timelines.
@Observable
final class WatchStore {
    /// The latest summary, or nil until the iPhone has sent one.
    private(set) var snapshot: WidgetSnapshot?
    /// True while waiting for the iPhone to answer `refresh()`.
    private(set) var isRefreshing = false
    /// When the iPhone last sent a summary during this run, even one with no changes.
    private(set) var lastHeardFromPhone: Date?

    /// The custom accent color chosen on the iPhone, or Stirling Money's purple.
    var accent: Color {
        snapshot?.accentColor.map { Color($0) } ?? Color("AccentColor")
    }

    /// How current the figures are: when the iPhone last confirmed them, or when they last changed.
    /// The iPhone only rewrites the summary when something changes, so its date alone can look stale.
    var asOf: Date? {
        guard let snapshot else { return nil }
        return max(snapshot.updatedAt, lastHeardFromPhone ?? .distantPast)
    }

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var receiver: SessionReceiver?

    nonisolated private static let log = Logger(subsystem: "net.s-church.stirlingmoney.watchkitapp", category: "WatchStore")

    /// - Parameters:
    ///   - fileURL: where the summary is saved; the App Group folder by default. Tests pass a temporary file.
    ///   - snapshot: a summary to start with instead of the saved one, for previews.
    init(fileURL: URL? = WidgetSnapshot.fileURL, snapshot: WidgetSnapshot? = nil) {
        self.fileURL = fileURL
        self.snapshot = snapshot ?? fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap(Self.decode)
    }

    /// Starts listening to the iPhone. Call once, at launch.
    func start() {
        guard WCSession.isSupported(), receiver == nil else { return }
        let receiver = SessionReceiver { [weak self] data in
            Task { @MainActor in self?.receive(data) }
        }
        self.receiver = receiver
        WCSession.default.delegate = receiver
        WCSession.default.activate()
    }

    /// Asks the iPhone for a fresh summary, if it's reachable. Otherwise the last one stays.
    func refresh() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable, !isRefreshing else { return }
        isRefreshing = true
        session.sendMessage(
            [WatchMessage.requestKey: true],
            // Both handlers run on WatchConnectivity's queue, so they mustn't be main-actor closures.
            replyHandler: { @Sendable [weak self] reply in
                let data = reply[WatchMessage.snapshotKey] as? Data
                Task { @MainActor in
                    self?.isRefreshing = false
                    if let data {
                        self?.receive(data)
                    }
                }
            },
            errorHandler: { @Sendable [weak self] error in
                Self.log.error("The iPhone didn't answer: \(error.localizedDescription)")
                Task { @MainActor in self?.isRefreshing = false }
            }
        )
    }

    /// Takes a summary from the iPhone: keeps it if it's newer, saves it and redraws the complications.
    /// Returns whether it was kept.
    @discardableResult
    func receive(_ data: Data, now: Date = .now) -> Bool {
        guard let incoming = Self.decode(data) else {
            Self.log.error("Couldn't read a summary of \(data.count) bytes from the iPhone")
            return false
        }
        lastHeardFromPhone = now
        guard Self.isNewer(incoming, than: snapshot) else { return false }
        snapshot = incoming
        if let fileURL {
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                Self.log.error("Couldn't save the summary: \(error.localizedDescription)")
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }

    /// Whether `incoming` should replace `current`. A reply and an application context can arrive in
    /// either order, so an older summary never replaces a newer one.
    nonisolated static func isNewer(_ incoming: WidgetSnapshot, than current: WidgetSnapshot?) -> Bool {
        guard let current else { return true }
        return incoming.updatedAt >= current.updatedAt
    }

    nonisolated static func decode(_ data: Data) -> WidgetSnapshot? {
        try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

/// The WatchConnectivity delegate. Its callbacks arrive on a background queue, so it only hands the
/// summary's bytes to `onSnapshot`, which hops to the main actor.
private final nonisolated class SessionReceiver: NSObject, WCSessionDelegate, Sendable {
    private let onSnapshot: @Sendable (Data) -> Void

    init(onSnapshot: @escaping @Sendable (Data) -> Void) {
        self.onSnapshot = onSnapshot
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        // The newest context the iPhone sent, possibly while this app wasn't running.
        if activationState == .activated, let data = session.receivedApplicationContext[WatchMessage.snapshotKey] as? Data {
            onSnapshot(data)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext[WatchMessage.snapshotKey] as? Data {
            onSnapshot(data)
        }
    }
}
