import SwiftUI
import WidgetKit

struct BudgetComplicationEntry: TimelineEntry {
    let date: Date
    /// nil when there's no summary yet, no budgets, or the chosen budget is gone.
    let budget: WidgetSnapshot.BudgetSummary?
    var accent: Color = .init("AccentColor")
}

struct BudgetComplicationProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BudgetComplicationEntry {
        BudgetComplicationEntry(date: .now, budget: WidgetSnapshot.sample.budgets.first)
    }

    func snapshot(for configuration: SelectBudgetIntent, in context: Context) async -> BudgetComplicationEntry {
        entry(for: configuration, snapshot: WidgetSnapshot.load() ?? (context.isPreview ? .sample : nil), on: .now)
    }

    func timeline(for configuration: SelectBudgetIntent, in context: Context) async -> Timeline<BudgetComplicationEntry> {
        let entry = entry(for: configuration, snapshot: WidgetSnapshot.load(), on: .now)
        // Amounts change when the Watch app receives a new summary. Also redraw when the period ends, so the
        // complication stops showing last period's figures.
        if let budget = entry.budget, budget.isCurrent(on: entry.date) {
            return Timeline(entries: [entry], policy: .after(budget.periodEnd))
        }
        return Timeline(entries: [entry], policy: .never)
    }

    /// The watch face editor lists each budget.
    func recommendations() -> [AppIntentRecommendation<SelectBudgetIntent>] {
        (WidgetSnapshot.load()?.budgets ?? []).map { budget in
            let intent = SelectBudgetIntent()
            intent.budget = BudgetEntity(id: budget.id, name: budget.name)
            return AppIntentRecommendation(intent: intent, description: Text(budget.name))
        }
    }

    private func entry(for configuration: SelectBudgetIntent, snapshot: WidgetSnapshot?, on date: Date) -> BudgetComplicationEntry {
        let accent = complicationAccent(snapshot)
        // Not configured yet: the first budget.
        let budget = configuration.budget.map { wanted in snapshot?.budgets.first { $0.id == wanted.id } } ?? snapshot?.budgets.first
        return BudgetComplicationEntry(date: date, budget: budget, accent: accent)
    }
}

struct BudgetComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BudgetComplicationEntry

    var body: some View {
        if let budget = entry.budget {
            if budget.isCurrent(on: entry.date) {
                current(budget)
            } else {
                ended(budget)
            }
        } else {
            switch family {
            case .accessoryInline:
                Text("No budgets")
            case .accessoryRectangular:
                Text("Add a budget in Stirling Money on your iPhone.")
                    .font(.footnote)
            default:
                Image(systemName: "chart.bar")
                    .font(.title3)
                    .widgetAccentable()
            }
        }
    }

    @ViewBuilder
    private func current(_ budget: WidgetSnapshot.BudgetSummary) -> some View {
        // Over budget is red whatever the accent color.
        let tint = budget.isOverBudget ? Color.red : entry.accent
        switch family {
        case .accessoryCircular:
            Gauge(value: budget.progress) {
                Image(systemName: "chart.bar.fill")
            } currentValueLabel: {
                // What's left, or how much over (negative).
                Text(budget.remaining, format: .localCurrency.notation(.compactName))
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(tint)
            .widgetAccentable()
        case .accessoryCorner:
            Text(budget.remaining, format: .localCurrency.notation(.compactName))
                .font(.system(size: 14, weight: .semibold))
                .minimumScaleFactor(0.6)
                .widgetLabel {
                    Gauge(value: budget.progress) {
                        Text(budget.name)
                    }
                    .tint(tint)
                }
        case .accessoryInline:
            Text("\(budget.name): \(leftOrOver(budget))")
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text(budget.name)
                    .font(.headline)
                    .foregroundStyle(entry.accent)
                    .widgetAccentable()
                    .lineLimit(1)
                Gauge(value: budget.progress) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(tint)
                .widgetAccentable()
                leftOrOver(budget)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(budget.isOverBudget ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The period these figures were for has ended; the iPhone has to send new ones.
    @ViewBuilder
    private func ended(_ budget: WidgetSnapshot.BudgetSummary) -> some View {
        switch family {
        case .accessoryInline:
            Text("\(budget.name): open iPhone app")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(budget.name)
                    .font(.headline)
                    .foregroundStyle(entry.accent)
                    .widgetAccentable()
                    .lineLimit(1)
                Text("Open Stirling Money on your iPhone to update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Image(systemName: "arrow.clockwise")
                .font(.title3)
                .widgetAccentable()
                .accessibilityLabel("Open Stirling Money on your iPhone to update \(budget.name)")
        }
    }

    private func leftOrOver(_ budget: WidgetSnapshot.BudgetSummary) -> Text {
        if budget.isOverBudget {
            Text("\(-budget.remaining, format: .localCurrency) over")
        } else {
            Text("\(budget.remaining, format: .localCurrency) left")
        }
    }
}

struct BudgetComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WatchBudget", intent: SelectBudgetIntent.self, provider: BudgetComplicationProvider()) { entry in
            BudgetComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Budget")
        .description("A budget's spending this period.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    BudgetComplication()
} timeline: {
    BudgetComplicationEntry(date: .now, budget: WidgetSnapshot.sample.budgets[0])
    BudgetComplicationEntry(date: .now, budget: WidgetSnapshot.sample.budgets[1])
    BudgetComplicationEntry(date: .now, budget: nil)
}

#Preview("Circular", as: .accessoryCircular) {
    BudgetComplication()
} timeline: {
    BudgetComplicationEntry(date: .now, budget: WidgetSnapshot.sample.budgets[0])
    BudgetComplicationEntry(date: .now, budget: WidgetSnapshot.sample.budgets[1])
}

#Preview("Corner", as: .accessoryCorner) {
    BudgetComplication()
} timeline: {
    BudgetComplicationEntry(date: .now, budget: WidgetSnapshot.sample.budgets[0])
}
