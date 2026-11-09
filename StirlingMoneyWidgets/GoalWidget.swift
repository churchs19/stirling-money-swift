import SwiftUI
import WidgetKit

struct GoalEntry: TimelineEntry {
    let date: Date
    /// nil when there's no goal to show.
    let goal: WidgetSnapshot.GoalSummary?
    let message: LocalizedStringKey
    /// The accent color chosen in the app, for the gauge.
    var accent: Color = WidgetAccent.standard
}

struct GoalProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GoalEntry {
        GoalEntry(date: .now, goal: WidgetSnapshot.sample.goals.first, message: "", accent: WidgetAccent.current)
    }

    func snapshot(for configuration: SelectGoalIntent, in context: Context) async -> GoalEntry {
        if context.isPreview, WidgetSnapshot.load() == nil {
            return placeholder(in: context)
        }
        return entry(for: configuration, on: .now)
    }

    func timeline(for configuration: SelectGoalIntent, in context: Context) async -> Timeline<GoalEntry> {
        // Days left changes at midnight; balances change when the app writes new data.
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86400))
        return Timeline(entries: [entry(for: configuration, on: .now)], policy: .after(midnight))
    }

    private func entry(for configuration: SelectGoalIntent, on date: Date) -> GoalEntry {
        guard let snapshot = WidgetSnapshot.load() else {
            return GoalEntry(date: date, goal: nil, message: "Open Stirling Money to see your goals.")
        }
        guard let wanted = configuration.goal else {
            // Not configured yet: show the first goal, if there is one.
            if let first = snapshot.goals.first {
                return GoalEntry(date: date, goal: first, message: "", accent: WidgetAccent.current)
            }
            return GoalEntry(date: date, goal: nil, message: "Add a goal in Stirling Money.")
        }
        if let goal = snapshot.goals.first(where: { $0.id == wanted.id }) {
            return GoalEntry(date: date, goal: goal, message: "", accent: WidgetAccent.current)
        }
        return GoalEntry(date: date, goal: nil, message: "This goal was deleted. Edit the widget to choose another.")
    }
}

struct GoalWidgetView: View {
    let entry: GoalEntry

    var body: some View {
        if let goal = entry.goal {
            let remaining = max(goal.targetAmount - goal.currentAmount, 0)
            let days = Calendar.current.dateComponents(
                [.day], from: Calendar.current.startOfDay(for: entry.date), to: Calendar.current.startOfDay(for: goal.targetDate)
            ).day ?? 0

            VStack(alignment: .leading, spacing: 6) {
                Gauge(value: goal.progress) {
                    EmptyView()
                } currentValueLabel: {
                    Text(goal.progress, format: .percent.precision(.fractionLength(0)))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                // Completed goals stay green whatever the accent color.
                .tint(remaining == 0 ? .green : entry.accent)
                .scaleEffect(0.75)
                .frame(width: 40, height: 40)
                Text(goal.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if remaining == 0 {
                    Label("Reached", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                } else {
                    Text("\(remaining, format: .localCurrency) to go")
                        .font(.subheadline.bold())
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Group {
                        if days > 0 {
                            Text("^[\(days) day](inflect: true) left")
                        } else if days == 0 {
                            Text("Due today")
                        } else {
                            Text("^[\(-days) day](inflect: true) overdue")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(days < 0 ? .red : .secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            WidgetMessage(text: entry.message)
        }
    }
}

struct GoalWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Goal", intent: SelectGoalIntent.self, provider: GoalProvider()) { entry in
            GoalWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                // Opens the app's Goals tab. Matches `DeepLink.goals` in the app; keep them in step.
                .widgetURL(URL(string: "stirlingmoney://goals"))
        }
        .configurationDisplayName("Goal")
        .description("Progress toward a savings goal.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    GoalWidget()
} timeline: {
    GoalEntry(date: .now, goal: WidgetSnapshot.sample.goals[0], message: "")
    GoalEntry(date: .now, goal: nil, message: "Add a goal in Stirling Money.")
}
