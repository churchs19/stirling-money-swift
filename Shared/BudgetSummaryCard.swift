import SwiftUI

/// One budget from the summary (`WidgetSnapshot.BudgetSummary`), laid out like a card on the app's Budgets
/// screen (`BudgetRow`): name and what it covers, a bar (red when over), spent of the limit, what's left or over,
/// and the period. Used by the widgets, the Watch app and the complications; the app itself uses `BudgetRow`.
struct BudgetSummaryCard: View {
    enum Style {
        /// As on the Budgets screen.
        case full
        /// As on the Budgets screen without the period line, for stacking several in a medium widget.
        case dense
        /// Stacked for narrow spaces (a small widget, the Watch): "$X left" without "of $Y", dates without the year.
        case compact
    }

    let budget: WidgetSnapshot.BudgetSummary
    /// The accent color chosen in the app, for the bar.
    let accent: Color
    var style: Style = .full
    /// Today, to tell whether the figures are still for the current period.
    var now: Date = .now

    var body: some View {
        VStack(alignment: .leading, spacing: style == .full ? 6 : 4) {
            heading

            if budget.isCurrent(on: now) {
                ProgressView(value: budget.progress)
                    .tint(budget.isOverBudget ? .red : accent)
                    .accessibilityHidden(true)
                amounts
                if style != .dense {
                    Text(budget.periodText(withYear: style == .full))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                // The iPhone worked these figures out for a period that has since ended.
                Text(Self.updateMessage)
                    .font(style == .compact ? .footnote : .subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    private var categoryName: String {
        budget.categoryName ?? String(localized: "All Spending")
    }

    @ViewBuilder private var heading: some View {
        switch style {
        case .full, .dense:
            HStack(alignment: .firstTextBaseline) {
                Text(budget.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(categoryName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        case .compact:
            VStack(alignment: .leading, spacing: 0) {
                Text(budget.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(categoryName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder private var amounts: some View {
        switch style {
        case .full, .dense:
            HStack(alignment: .firstTextBaseline) {
                Text("\(budget.spent, format: .localCurrency) of \(budget.amount, format: .localCurrency)")
                Spacer()
                leftOrOver
                    .foregroundStyle(budget.isOverBudget ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        case .compact:
            leftOrOver
                .foregroundStyle(budget.isOverBudget ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var leftOrOver: Text {
        if budget.isOverBudget {
            Text("\(-budget.remaining, format: .localCurrency) over")
        } else {
            Text("\(budget.remaining, format: .localCurrency) left")
        }
    }

    private static var updateMessage: LocalizedStringKey {
        #if os(watchOS)
            "Open Stirling Money on your iPhone to update."
        #else
            "Open Stirling Money to update."
        #endif
    }
}

extension WidgetSnapshot {
    /// The budgets a list widget with room for `capacity` cards shows, in the summary's order (by name, as on the
    /// Budgets screen), and how many it leaves out.
    static func budgetsToList(_ budgets: [BudgetSummary], capacity: Int) -> (shown: [BudgetSummary], more: Int) {
        let shown = Array(budgets.prefix(max(capacity, 0)))
        return (shown, budgets.count - shown.count)
    }
}

extension WidgetSnapshot.BudgetSummary {
    /// "Monthly · Nov 1 – 30, 2026", as on the Budgets screen, or without the year for small spaces.
    /// Summaries written before `periodTitle` was added show just the dates.
    func periodText(withYear: Bool, calendar: Calendar = .current) -> String {
        // `periodEnd` is the start of the day after the last day.
        let lastDay = calendar.date(byAdding: .day, value: -1, to: periodEnd) ?? periodEnd
        let days: String
        if lastDay > periodStart {
            let style = Date.IntervalFormatStyle.interval.month(.abbreviated).day()
            days = (periodStart ..< lastDay).formatted(withYear ? style.year() : style)
        } else {
            days = periodStart.formatted(.dateTime.month(.abbreviated).day())
        }
        guard let periodTitle else { return days }
        return "\(periodTitle) · \(days)"
    }
}

#Preview("Full") {
    List(WidgetSnapshot.sample.budgets) { budget in
        BudgetSummaryCard(budget: budget, accent: .purple)
    }
}

#Preview("Compact") {
    List(WidgetSnapshot.sample.budgets) { budget in
        BudgetSummaryCard(budget: budget, accent: .purple, style: .compact)
    }
}

#Preview("Ended period") {
    List(WidgetSnapshot.sample.budgets) { budget in
        BudgetSummaryCard(budget: budget, accent: .purple, now: .now.addingTimeInterval(86400 * 30))
    }
}
