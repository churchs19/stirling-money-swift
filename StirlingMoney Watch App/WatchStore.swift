import Foundation
import Observation
import os
import SwiftUI
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
    /// The day the pages show. Moved on whenever the app comes to the front (`showToday()`).
    private(set) var today = Date.now

    /// The summary as of `today`: recurring transactions the iPhone hasn't added yet count from the day they fall
    /// due (`WidgetSnapshot.projected(on:)`).
    var current: WidgetSnapshot? {
        snapshot?.projected(on: today)
    }

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

    private nonisolated static let log = Logger(subsystem: "net.s-church.stirlingmoney.watchkitapp", category: "WatchStore")

    /// - Parameters:
    ///   - fileURL: where the summary is saved; the App Group folder by default. Tests pass a temporary file.
    ///   - snapshot: a summary to start with instead of the saved one, for previews.
    init(fileURL: URL? = WidgetSnapshot.fileURL, snapshot: WidgetSnapshot? = nil) {
        self.fileURL = fileURL
        self.snapshot = snapshot ?? fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap(Self.decode)
    }

    /// Starts listening to the iPhone. Call once, at launch.
    func start() {
        // Rebuild the watch face editor's choices from the saved summary, in case the system cached
        // them before any summary arrived (it then offers only "All Accounts" and no goals).
        WidgetCenter.shared.invalidateConfigurationRecommendations()
        guard WCSession.isSupported(), receiver == nil else { return }
        let receiver = SessionReceiver(
            onSnapshot: { [weak self] data in
                Task { @MainActor in self?.receive(data) }
            },
            // `refresh()` at launch usually runs before the session has activated, so ask again once
            // it's ready, and whenever the iPhone comes back in range.
            onReachable: { [weak self] in
                Task { @MainActor in self?.refresh() }
            }
        )
        self.receiver = receiver
        WCSession.default.delegate = receiver
        WCSession.default.activate()
    }

    /// Shows the summary as of now, such as when the app comes back to the front on a later day.
    func showToday(_ now: Date = .now) {
        today = now
    }

    /// Asks the iPhone for a fresh summary, if it's reachable. Otherwise the last one stays.
    func refresh() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable, !isRefreshing else {
            Self.log.notice("Not asking the iPhone: activated \(session.activationState == .activated), reachable \(session.isReachable)")
            return
        }
        Self.log.notice("Asking the iPhone for a summary")
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
        let choicesChanged = Self.complicationChoicesChanged(from: snapshot, to: incoming)
        snapshot = incoming
        if let fileURL {
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                Self.log.error("Couldn't save the summary: \(error.localizedDescription)")
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        if choicesChanged {
            // The watch face editor's list of accounts and goals comes from the complications'
            // `recommendations()`, which the system caches until told otherwise.
            WidgetCenter.shared.invalidateConfigurationRecommendations()
        }
        return true
    }

    /// Whether the accounts, goals or budgets a complication can show (their IDs and names) differ.
    nonisolated static func complicationChoicesChanged(from old: WidgetSnapshot?, to new: WidgetSnapshot) -> Bool {
        func choices(_ snapshot: WidgetSnapshot?) -> [[String]] {
            [
                snapshot?.accounts.flatMap { [$0.id, $0.name] } ?? [],
                snapshot?.goals.flatMap { [$0.id, $0.name] } ?? [],
                snapshot?.budgets.flatMap { [$0.id, $0.name] } ?? [],
            ]
        }
        return choices(old) != choices(new)
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
/// summary's bytes to `onSnapshot` and reachability to `onReachable`, which hop to the main actor.
private final nonisolated class SessionReceiver: NSObject, WCSessionDelegate, Sendable {
    private let onSnapshot: @Sendable (Data) -> Void
    private let onReachable: @Sendable () -> Void

    private static let log = Logger(subsystem: "net.s-church.stirlingmoney.watchkitapp", category: "WatchStore")

    init(onSnapshot: @escaping @Sendable (Data) -> Void, onReachable: @escaping @Sendable () -> Void) {
        self.onSnapshot = onSnapshot
        self.onReachable = onReachable
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        if let error {
            Self.log.error("Session didn't activate: \(error.localizedDescription)")
        }
        let context = session.receivedApplicationContext[WatchMessage.snapshotKey] as? Data
        Self.log.notice("Session activated: \(activationState == .activated), reachable \(session.isReachable), context \(context?.count ?? 0) bytes")
        guard activationState == .activated else { return }
        // The newest context the iPhone sent, possibly while this app wasn't running.
        if let context {
            onSnapshot(context)
        }
        if session.isReachable {
            onReachable()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.activationState == .activated, session.isReachable {
            onReachable()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext[WatchMessage.snapshotKey] as? Data {
            onSnapshot(data)
        }
    }
}
