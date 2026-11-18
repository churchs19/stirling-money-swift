import SwiftUI
import WidgetKit

struct BudgetListEntry: TimelineEntry {
    let date: Date
    /// nil when the app hasn't written any data yet.
    let budgets: [WidgetSnapshot.BudgetSummary]?
    /// The accent color chosen in the app, for the bars.
    var accent: Color = WidgetAccent.standard
}

struct BudgetListProvider: TimelineProvider {
    func placeholder(in context: Context) -> BudgetListEntry {
        BudgetListEntry(date: .now, budgets: WidgetSnapshot.sample.budgets, accent: WidgetAccent.current)
    }

    func getSnapshot(in context: Context, completion: @escaping (BudgetListEntry) -> Void) {
        if context.isPreview, WidgetSnapshot.load()?.budgets.isEmpty ?? true {
            completion(placeholder(in: context))
        } else {
            completion(currentEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetListEntry>) -> Void) {
        let entry = currentEntry()
        // The app reloads widgets when it writes new data. Also redraw when the first period ends, so that
        // budget asks for the app to be opened instead of showing last period's figures.
        let nextEnd = entry.budgets?
            .filter { $0.isCurrent(on: entry.date) }
            .map(\.periodEnd)
            .min()
        completion(Timeline(entries: [entry], policy: nextEnd.map { .after($0) } ?? .never))
    }

    private func currentEntry() -> BudgetListEntry {
        BudgetListEntry(date: .now, budgets: WidgetSnapshot.load()?.budgets, accent: WidgetAccent.current)
    }
}

struct BudgetListWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BudgetListEntry

    var body: some View {
        if let budgets = entry.budgets {
            if budgets.isEmpty {
                WidgetMessage(text: "Add a budget in Stirling Money.")
            } else {
                list(budgets)
            }
        } else {
            WidgetMessage(text: "Open Stirling Money to see your budgets.")
        }
    }

    /// How many cards fit, and in how many columns.
    private var layout: (capacity: Int, columns: Int, style: BudgetSummaryCard.Style) {
        switch family {
        case .systemLarge: (3, 1, .full)
        case .systemExtraLarge: (6, 2, .full)
        default: (2, 1, .dense)
        }
    }

    @ViewBuilder
    private func list(_ budgets: [WidgetSnapshot.BudgetSummary]) -> some View {
        let layout = layout
        let (shown, more) = WidgetSnapshot.budgetsToList(budgets, capacity: layout.capacity)

        VStack(alignment: .leading, spacing: layout.style == .dense ? 8 : 10) {
            // The medium widget has no room for a heading.
            if family != .systemMedium {
                header(more: more)
            }
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: layout.style == .dense ? 10 : 12) {
                ForEach(rows(shown, columns: layout.columns), id: \.first?.id) { row in
                    GridRow {
                        ForEach(row) { budget in
                            BudgetSummaryCard(budget: budget, accent: entry.accent, style: layout.style, now: entry.date)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(more: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Budgets")
                .font(.subheadline.bold())
                .foregroundStyle(entry.accent)
                .widgetAccentable()
            Spacer()
            if more > 0 {
                Text("+\(more) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The budgets in rows of `columns`, reading across.
    private func rows(_ budgets: [WidgetSnapshot.BudgetSummary], columns: Int) -> [[WidgetSnapshot.BudgetSummary]] {
        stride(from: 0, to: budgets.count, by: columns).map { Array(budgets[$0 ..< min($0 + columns, budgets.count)]) }
    }
}

struct BudgetListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BudgetList", provider: BudgetListProvider()) { entry in
            BudgetListWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                // Opens the app's Budgets tab. Matches `DeepLink.budgets` in the app; keep them in step.
                .widgetURL(URL(string: "stirlingmoney://budgets"))
        }
        .configurationDisplayName("All Budgets")
        .description("Every budget's spending this period.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

/// More budgets than the sample has, to fill the larger sizes.
private var previewBudgets: [WidgetSnapshot.BudgetSummary] {
    let base = WidgetSnapshot.sample.budgets
    let more: [(String, String?, Decimal, Decimal)] = [
        ("Dining", "Restaurants", 200, 80), ("Fuel", "Gas", 160, 150), ("Gifts", nil, 300, 40),
        ("Home", "Household", 250, 260), ("Kids", "Childcare", 500, 120), ("Pets", "Pet Care", 90, 30),
    ]
    return base + more.enumerated().map { index, item in
        var budget = base[0]
        budget.id = "preview\(index)"
        budget.name = item.0
        budget.categoryName = item.1
        budget.amount = item.2
        budget.spent = item.3
        return budget
    }
}

#Preview("Medium", as: .systemMedium) {
    BudgetListWidget()
} timeline: {
    BudgetListEntry(date: .now, budgets: previewBudgets)
    BudgetListEntry(date: .now, budgets: [])
}

#Preview("Large", as: .systemLarge) {
    BudgetListWidget()
} timeline: {
    BudgetListEntry(date: .now, budgets: previewBudgets)
}

#if os(iOS)
    #Preview("Extra Large", as: .systemExtraLarge) {
        BudgetListWidget()
    } timeline: {
        BudgetListEntry(date: .now, budgets: previewBudgets)
    }
#endif
