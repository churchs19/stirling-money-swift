import SwiftUI
import WidgetKit

struct BudgetEntry: TimelineEntry {
    let date: Date
    /// nil when there's no budget to show.
    let budget: WidgetSnapshot.BudgetSummary?
    let message: LocalizedStringKey
    /// The accent color chosen in the app, for the bar.
    var accent: Color = WidgetAccent.standard
}

struct BudgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BudgetEntry {
        BudgetEntry(date: .now, budget: WidgetSnapshot.sample.budgets.first, message: "", accent: WidgetAccent.current)
    }

    func snapshot(for configuration: SelectBudgetIntent, in context: Context) async -> BudgetEntry {
        if context.isPreview, WidgetSnapshot.load()?.budgets.isEmpty ?? true {
            return placeholder(in: context)
        }
        return entry(for: configuration, on: .now)
    }

    func timeline(for configuration: SelectBudgetIntent, in context: Context) async -> Timeline<BudgetEntry> {
        let entry = entry(for: configuration, on: .now)
        // The app reloads widgets when it writes new data. Also redraw when the period ends, so the widget
        // asks for the app to be opened instead of showing last period's figures.
        if let budget = entry.budget, budget.isCurrent(on: entry.date) {
            return Timeline(entries: [entry], policy: .after(budget.periodEnd))
        }
        return Timeline(entries: [entry], policy: .never)
    }

    private func entry(for configuration: SelectBudgetIntent, on date: Date) -> BudgetEntry {
        switch WidgetChoice.choose(id: configuration.budget?.id, from: WidgetSnapshot.load()?.budgets) {
        case let .item(budget):
            BudgetEntry(date: date, budget: budget, message: "", accent: WidgetAccent.current)
        case .noSummary:
            BudgetEntry(date: date, budget: nil, message: "Open Stirling Money to see your budgets.")
        case .noneExist:
            BudgetEntry(date: date, budget: nil, message: "Add a budget in Stirling Money.")
        case .missing:
            // Deleted, or its period ended and the app has left it out of the summary.
            BudgetEntry(date: date, budget: nil, message: "This budget isn't available. Edit the widget to choose another.")
        }
    }
}

struct BudgetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BudgetEntry

    var body: some View {
        if let budget = entry.budget {
            content(budget)
        } else {
            WidgetMessage(text: entry.message)
        }
    }

    @ViewBuilder
    private func content(_ budget: WidgetSnapshot.BudgetSummary) -> some View {
        switch family {
        #if os(iOS)
            case .accessoryInline:
                if budget.isCurrent(on: entry.date) {
                    Text("\(budget.name): \(leftOrOver(budget))")
                } else {
                    Text("\(budget.name): open Stirling Money")
                }
            case .accessoryCircular:
                if budget.isCurrent(on: entry.date) {
                    Gauge(value: budget.progress) {
                        Text(budget.name)
                    } currentValueLabel: {
                        // What's left, or how much over (negative).
                        Text(budget.remaining, format: .localCurrency.notation(.compactName))
                            .minimumScaleFactor(0.5)
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .widgetAccentable()
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .widgetAccentable()
                        .accessibilityLabel("Open Stirling Money to update \(budget.name)")
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(budget.name)
                        .font(.headline)
                        .widgetAccentable()
                        .lineLimit(1)
                    if budget.isCurrent(on: entry.date) {
                        Gauge(value: budget.progress) {
                            EmptyView()
                        }
                        .gaugeStyle(.accessoryLinearCapacity)
                        leftOrOver(budget)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        Text("Open Stirling Money to update.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        #endif
        case .systemMedium:
            BudgetSummaryCard(budget: budget, accent: entry.accent, now: entry.date)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            VStack(alignment: .leading, spacing: 0) {
                BudgetSummaryCard(budget: budget, accent: entry.accent, style: .compact, now: entry.date)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

struct BudgetWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Budget", intent: SelectBudgetIntent.self, provider: BudgetProvider()) { entry in
            BudgetWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                // Opens the app's Budgets tab. Matches `DeepLink.budgets` in the app; keep them in step.
                .widgetURL(URL(string: "stirlingmoney://budgets"))
        }
        .configurationDisplayName("Budget")
        .description("One budget's spending this period.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
            [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline]
        #else
            [.systemSmall, .systemMedium]
        #endif
    }
}

/// A budget whose period ended before the app wrote a new summary.
private var endedBudget: WidgetSnapshot.BudgetSummary {
    var budget = WidgetSnapshot.sample.budgets[0]
    budget.periodStart = .now.addingTimeInterval(-86400 * 40)
    budget.periodEnd = .now.addingTimeInterval(-86400 * 10)
    return budget
}

#Preview("Small", as: .systemSmall) {
    BudgetWidget()
} timeline: {
    BudgetEntry(date: .now, budget: WidgetSnapshot.sample.budgets[0], message: "")
    BudgetEntry(date: .now, budget: WidgetSnapshot.sample.budgets[1], message: "")
    BudgetEntry(date: .now, budget: endedBudget, message: "")
    BudgetEntry(date: .now, budget: nil, message: "Add a budget in Stirling Money.")
}

#Preview("Medium", as: .systemMedium) {
    BudgetWidget()
} timeline: {
    BudgetEntry(date: .now, budget: WidgetSnapshot.sample.budgets[0], message: "")
    BudgetEntry(date: .now, budget: WidgetSnapshot.sample.budgets[1], message: "")
}

#if os(iOS)
    #Preview("Lock Screen", as: .accessoryRectangular) {
        BudgetWidget()
    } timeline: {
        BudgetEntry(date: .now, budget: WidgetSnapshot.sample.budgets[0], message: "")
        BudgetEntry(date: .now, budget: WidgetSnapshot.sample.budgets[1], message: "")
    }

    #Preview("Circular", as: .accessoryCircular) {
        BudgetWidget()
    } timeline: {
        BudgetEntry(date: .now, budget: WidgetSnapshot.sample.budgets[0], message: "")
        BudgetEntry(date: .now, budget: WidgetSnapshot.sample.budgets[1], message: "")
    }
#endif
