import SwiftUI
import WidgetKit

struct GoalComplicationEntry: TimelineEntry {
    let date: Date
    /// nil when there's no summary yet, no goals, or the chosen goal was deleted; `emptyState` says which.
    let goal: WidgetSnapshot.GoalSummary?
    var accent: Color = Color("AccentColor")
    var emptyState: ComplicationEmptyState = .noSummary
}

struct GoalComplicationProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GoalComplicationEntry {
        GoalComplicationEntry(date: .now, goal: WidgetSnapshot.sample.goals.first)
    }

    func snapshot(for configuration: SelectGoalIntent, in context: Context) async -> GoalComplicationEntry {
        entry(for: configuration, snapshot: (WidgetSnapshot.load() ?? (context.isPreview ? .sample : nil))?.projected(on: .now), on: .now)
    }

    func timeline(for configuration: SelectGoalIntent, in context: Context) async -> Timeline<GoalComplicationEntry> {
        // Days left changes at midnight; amounts change when the Watch app receives a new summary, and when
        // recurring transactions fall due.
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86400))
        let summary = WidgetSnapshot.load()
        let dates = summary?.timelineDates(now: .now, adding: [midnight]) ?? [.now]
        let entries = dates.map { entry(for: configuration, snapshot: summary?.projected(on: $0), on: $0) }
        return Timeline(entries: entries, policy: dates.count > 1 ? .atEnd : .after(midnight))
    }

    /// The watch face editor lists each goal.
    func recommendations() -> [AppIntentRecommendation<SelectGoalIntent>] {
        (WidgetSnapshot.load()?.goals ?? []).map { goal in
            let intent = SelectGoalIntent()
            intent.goal = GoalEntity(id: goal.id, name: goal.name)
            return AppIntentRecommendation(intent: intent, description: Text(goal.name))
        }
    }

    private func entry(for configuration: SelectGoalIntent, snapshot: WidgetSnapshot?, on date: Date) -> GoalComplicationEntry {
        let accent = complicationAccent(snapshot)
        let choice = WidgetChoice.choose(id: configuration.goal?.id, from: snapshot?.goals)
        return GoalComplicationEntry(date: date, goal: choice.item, accent: accent, emptyState: ComplicationEmptyState(choice))
    }
}

struct GoalComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GoalComplicationEntry

    var body: some View {
        if let goal = entry.goal {
            let remaining = max(goal.targetAmount - goal.currentAmount, 0)
            // Reached goals are green whatever the accent color.
            let tint = remaining == 0 ? Color.green : entry.accent
            switch family {
            case .accessoryCircular:
                Gauge(value: goal.progress) {
                    Image(systemName: "flag.fill")
                } currentValueLabel: {
                    Text(goal.progress, format: .percent.precision(.fractionLength(0)))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(tint)
                .widgetAccentable()
            case .accessoryCorner:
                Text(goal.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 14, weight: .semibold))
                    .widgetLabel {
                        Gauge(value: goal.progress) {
                            Text(goal.name)
                        }
                        .tint(tint)
                    }
            case .accessoryInline:
                Text("\(goal.name) \(goal.progress, format: .percent.precision(.fractionLength(0)))")
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name)
                        .font(.headline)
                        .foregroundStyle(entry.accent)
                        .widgetAccentable()
                        .lineLimit(1)
                    Gauge(value: goal.progress) {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(tint)
                    .widgetAccentable()
                    if remaining == 0 {
                        Text("Reached")
                            .font(.caption)
                    } else {
                        Text("\(remaining, format: .localCurrency) to go · \(daysLeft(goal, on: entry.date))")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            switch entry.emptyState {
            case .noSummary:
                ComplicationMessage(inline: "Stirling Money", message: "Open Stirling Money on your iPhone.", systemImage: "flag")
            case .noneExist:
                ComplicationMessage(inline: "No goals", message: "Add a goal in Stirling Money on your iPhone.", systemImage: "flag")
            case .missing:
                ComplicationMessage(
                    inline: "Goal deleted",
                    message: "This goal was deleted. Edit the watch face to choose another.",
                    systemImage: "flag.slash"
                )
            }
        }
    }

    /// "12 days left", "Due today" or "3 days overdue".
    /// A `Text`, not a `String`: only `Text` applies the `inflect` plural markup.
    private func daysLeft(_ goal: WidgetSnapshot.GoalSummary, on date: Date) -> Text {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: goal.targetDate)
        ).day ?? 0
        if days > 0 {
            return Text("^[\(days) day](inflect: true) left")
        } else if days == 0 {
            return Text("Due today")
        } else {
            return Text("^[\(-days) day](inflect: true) overdue")
        }
    }
}

struct GoalComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WatchGoal", intent: SelectGoalIntent.self, provider: GoalComplicationProvider()) { entry in
            GoalComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Goal")
        .description("Progress toward a savings goal.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    GoalComplication()
} timeline: {
    GoalComplicationEntry(date: .now, goal: WidgetSnapshot.sample.goals[0])
    GoalComplicationEntry(date: .now, goal: nil, emptyState: .noneExist)
    GoalComplicationEntry(date: .now, goal: nil, emptyState: .missing)
}

#Preview("Circular", as: .accessoryCircular) {
    GoalComplication()
} timeline: {
    GoalComplicationEntry(date: .now, goal: WidgetSnapshot.sample.goals[0])
}
