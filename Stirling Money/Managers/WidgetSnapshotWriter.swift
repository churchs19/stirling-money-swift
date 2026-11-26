import Foundation
import SwiftData
import WidgetKit
#if os(macOS)
    import AppKit
#endif

/// Keeps the widgets' snapshot current, and asks widgets to refresh (and, on iPhone, sends it to the Watch)
/// when it changes.
///
/// The snapshot is rewritten at launch, shortly after every save of the main context (SwiftData autosaves soon
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
        // Bring the summary up to date at launch too: budget periods may have rolled over, and the
        // last run may have used different data (such as `-UseSampleData`). Only writes if it changed.
        scheduleUpdate()
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
            // The widgets and the Watch show the current book.
            let book = try Books.current(in: context, settings: LaunchMode.settings)
            let budgets = try context.fetch(FetchDescriptor(predicate: Budget.inBook(book)))
            // Every transaction is only needed for budgets that cover all spending.
            let transactions = budgets.contains { $0.category == nil }
                ? try context.fetch(FetchDescriptor(predicate: AccountTransaction.inBook(book)))
                : []
            let snapshot = try WidgetSnapshot(
                accounts: context.fetch(FetchDescriptor(predicate: Account.inBook(book))),
                goals: context.fetch(FetchDescriptor(predicate: Goal.inBook(book))),
                budgets: budgets,
                transactions: transactions,
                recurring: context.fetch(FetchDescriptor(predicate: RecurringTransaction.inBook(book))),
                accentColor: AccentChoice.sharedCustomColor,
                // Named only when there's more than one book, so a single book reads as before.
                bookName: context.fetchCount(FetchDescriptor<Book>()) > 1 ? book?.name : nil
            )
            guard snapshot.needsWrite(over: try? Data(contentsOf: url)) else { return }
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
