import Foundation
import os
import SwiftData
#if os(iOS)
    import BackgroundTasks
#endif
#if os(macOS)
    import AppKit
#endif

/// Runs `RecurringScheduler.addDue` at the right moments, so recurring transactions are added without opening the app
/// where the system allows it:
/// - at launch, whenever the app becomes active, and at midnight while it's open;
/// - on iPhone and iPad, in the background: after each run it asks iOS to wake the app at the earliest due date
///   (`scheduleBackgroundRefresh`). iOS decides when that actually happens, so it can be hours later;
/// - on the Mac, every hour while the app is open and when the Mac wakes. The Mac can't wake the app.
///
/// Not under tests: unit tests make their own rules, and UI tests need balances that don't change by date.
enum RecurringRunner {
    /// The background task, listed in `Stirling-Money-Info.plist` under `BGTaskSchedulerPermittedIdentifiers`.
    nonisolated static let taskIdentifier = "net.s-church.stirlingmoney.recurring"

    private static var context: ModelContext?
    private static var observers: [any NSObjectProtocol] = []
    private static var timer: Timer?
    private static let log = Logger(subsystem: "net.s-church.stirlingmoney", category: "Recurring")

    /// Starts running due transactions in `context`. Call once, at launch, after `WidgetSnapshotWriter` starts.
    static func start(_ context: ModelContext) {
        guard self.context == nil, !LaunchMode.isTesting else { return }
        self.context = context
        observers.append(
            NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { run() }
            }
        )
        #if os(macOS)
            observers.append(
                NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { run() }
                }
            )
            timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
                MainActor.assumeIsolated { run() }
            }
        #endif
        run()
    }

    /// Adds whatever is due, then schedules the next background run.
    static func run(now: Date = .now) {
        guard let context else { return }
        do {
            let added = try RecurringScheduler.addDue(in: context, now: now)
            if added > 0 {
                log.notice("Added \(added) recurring transactions")
            }
        } catch {
            log.error("Couldn't add recurring transactions: \(error.localizedDescription)")
        }
        scheduleBackgroundRefresh(now: now)
    }

    /// The background run: add what's due and write the widget summary straight away, before iOS suspends the app
    /// (the usual write waits a second after the save).
    static func runInBackground() {
        // Logged at notice level so it shows in a collected device log: proof that iOS woke the app.
        log.notice("Background run for recurring transactions")
        run()
        WidgetSnapshotWriter.updateNow()
    }

    /// When to ask iOS to wake the app: the next due day, or as soon as it likes if one is already due. nil when no
    /// rule will fall due.
    nonisolated static func earliestBeginDate(nextDue: Date?, now: Date) -> Date? {
        guard let nextDue else { return nil }
        return max(nextDue, now)
    }

    /// Asks iOS for a background run at the earliest due date, replacing any earlier request.
    static func scheduleBackgroundRefresh(now: Date = .now) {
        #if os(iOS)
            guard let context else { return }
            let scheduler = BGTaskScheduler.shared
            scheduler.cancel(taskRequestWithIdentifier: taskIdentifier)
            guard let begin = earliestBeginDate(nextDue: try? RecurringScheduler.nextDueDate(in: context), now: now) else { return }
            let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
            request.earliestBeginDate = begin
            Task {
                do {
                    try await scheduler.submitTaskRequest(request)
                } catch {
                    // The simulator doesn't run background tasks; on a device this is rare (too many requests).
                    log.notice("Couldn't schedule the background run: \(error.localizedDescription)")
                }
            }
        #endif
    }
}
