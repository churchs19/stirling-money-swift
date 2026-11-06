import Foundation
import SwiftData
import WidgetKit

/// Writes the widget snapshot and asks widgets to refresh, when the data has changed.
enum WidgetSnapshotWriter {
    static func update(from context: ModelContext) {
        guard let url = WidgetSnapshot.fileURL else { return }
        do {
            // Save first so the snapshot's identifiers are permanent, not temporary.
            try context.save()
            let snapshot = try WidgetSnapshot(
                accounts: context.fetch(FetchDescriptor<Account>()),
                goals: context.fetch(FetchDescriptor<Goal>())
            )
            if let existing = try? Data(contentsOf: url),
               var previous = try? JSONDecoder().decode(WidgetSnapshot.self, from: existing)
            {
                previous.updatedAt = snapshot.updatedAt
                if previous == snapshot { return }
            }
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Widgets keep showing the last snapshot; nothing else depends on this.
        }
    }
}
