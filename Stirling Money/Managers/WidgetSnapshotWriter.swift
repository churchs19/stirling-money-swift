import Foundation
import SwiftData
import WidgetKit
#if os(macOS)
    import AppKit
#endif

/// Keeps the widgets' snapshot current, and asks widgets to refresh (and, on iPhone, sends it to the Watch)
/// when it changes.
///
/// The snapshot is rewritten shortly after every save of the main context (SwiftData autosaves soon
/// after each change), when the app goes to the background, and when the Mac app quits. Going to the
/// background alone isn't enough on the Mac, where switching apps doesn't count.
enum WidgetSnapshotWriter {
    private static var context: ModelContext?
    private static var observers: [any NSObjectProtocol] = []
    private static var pendingUpdate: Task<Void, Never>?

    /// Starts refreshing the snapshot after each save of `context`. Call once, at launch.
    static func startObserving(_ context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        // Widgets otherwise keep showing what they last drew until their next scheduled refresh
        // (midnight for the Goal widget), so a new version of the app, with new links or layouts,
        // wouldn't show until then. Redraw them once at launch.
        WidgetCenter.shared.reloadAllTimelines()
        observers.append(
            NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context, queue: .main) { _ in
                MainActor.assumeIsolated { scheduleUpdate() }
            }
        )
        #if os(macOS)
            observers.append(
                NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { updateNow() }
                }
            )
        #endif
    }

    /// Updates the snapshot a moment from now, so a burst of saves (a transfer, an edit) writes once.
    static func scheduleUpdate() {
        pendingUpdate?.cancel()
        pendingUpdate = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            updateNow()
        }
    }

    /// Updates the snapshot straight away, such as when the app is going to the background or quitting.
    static func updateNow() {
        pendingUpdate?.cancel()
        guard let context else { return }
        update(from: context)
    }

    static func update(from context: ModelContext) {
        guard let url = WidgetSnapshot.fileURL else { return }
        do {
            // Save first so the snapshot's identifiers are permanent, not temporary.
            if context.hasChanges {
                try context.save()
            }
            let budgets = try context.fetch(FetchDescriptor<Budget>())
            // Every transaction is only needed for budgets that cover all spending.
            let transactions = budgets.contains { $0.category == nil }
                ? try context.fetch(FetchDescriptor<AccountTransaction>())
                : []
            let snapshot = try WidgetSnapshot(
                accounts: context.fetch(FetchDescriptor<Account>()),
                goals: context.fetch(FetchDescriptor<Goal>()),
                budgets: budgets,
                transactions: transactions,
                accentColor: AccentChoice.sharedCustomColor
            )
            if let existing = try? Data(contentsOf: url),
               var previous = try? JSONDecoder().decode(WidgetSnapshot.self, from: existing)
            {
                previous.updatedAt = snapshot.updatedAt
                if previous == snapshot { return }
            }
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
            #if os(iOS)
                WatchSync.shared.send(data)
            #endif
        } catch {
            // Widgets keep showing the last snapshot; nothing else depends on this.
        }
    }
}
