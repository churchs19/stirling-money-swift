import SwiftUI

/// Each savings goal: a progress ring, the amount to go and the days left.
struct GoalsPage: View {
    let goals: [WidgetSnapshot.GoalSummary]

    var body: some View {
        List {
            if goals.isEmpty {
                Text("No goals yet.")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(goals) { goal in
                        GoalRow(goal: goal)
                    }
                } header: {
                    BookHeader()
                } footer: {
                    UpdatedFooter()
                }
            }
        }
        .navigationTitle("Goals")
    }
}

private struct GoalRow: View {
    @Environment(WatchStore.self) private var store
    let goal: WidgetSnapshot.GoalSummary

    private var remaining: Decimal {
        max(goal.targetAmount - goal.currentAmount, 0)
    }

    var body: some View {
        HStack(spacing: 10) {
            Gauge(value: goal.progress) {
                EmptyView()
            } currentValueLabel: {
                Text(goal.progress, format: .percent.precision(.fractionLength(0)))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            // Reached goals are green whatever the accent color.
            .tint(remaining == 0 ? .green : store.accent)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(goal.name)
                    .font(.headline)
                    .lineLimit(2)
                if remaining == 0 {
                    Label("Reached", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("\(remaining, format: .localCurrency) to go")
                        .monospacedDigit()
                    DaysLeftText(targetDate: goal.targetDate)
                        .font(.footnote)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// "12 days left", "Due today" or "3 days overdue", as of today.
private struct DaysLeftText: View {
    let targetDate: Date

    var body: some View {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: targetDate)
        ).day ?? 0
        Group {
            if days > 0 {
                Text("^[\(days) day](inflect: true) left")
            } else if days == 0 {
                Text("Due today")
            } else {
                Text("^[\(-days) day](inflect: true) overdue")
            }
        }
        .foregroundStyle(days < 0 ? .red : .secondary)
    }
}

#Preview {
    NavigationStack {
        GoalsPage(goals: WidgetSnapshot.sample.goals)
    }
    .environment(WatchStore(fileURL: nil, snapshot: .sample))
}
