import SwiftData
import SwiftUI

/// A goal card: the account, progress toward the target, and days left or overdue.
struct GoalRow: View {
    let goal: Goal
    @Environment(\.appAccent) private var accent

    private var isReached: Bool {
        goal.amountRemaining == 0
    }

    var body: some View {
        let days = goal.daysRemaining()

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.name)
                    .font(.headline)
                Spacer()
                Text(goal.account?.name ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: goal.progress)
                .tint(isReached ? .green : accent)
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline) {
                Text("\(goal.currentAmount, format: .localCurrency) of \(goal.targetAmount, format: .localCurrency)")
                    .monospacedDigit()
                Spacer()
                if isReached {
                    Label("Reached", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("\(goal.amountRemaining, format: .localCurrency) to go")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)

            Group {
                if isReached {
                    Text("Target date \(goal.targetDate, format: .dateTime.month(.abbreviated).day().year())")
                } else if days > 0 {
                    Text("^[\(days) day](inflect: true) left · \(goal.targetDate, format: .dateTime.month(.abbreviated).day().year())")
                } else if days == 0 {
                    Text("Due today")
                } else {
                    Text("^[\(-days) day](inflect: true) overdue · \(goal.targetDate, format: .dateTime.month(.abbreviated).day().year())")
                        .foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        // Otherwise the separator lines up with the first text after an icon, such as "Reached".
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let container = ModelContainer.preview
    let goals = try! container.mainContext.fetch(FetchDescriptor<Goal>())
    return List(goals) { GoalRow(goal: $0) }
        .modelContainer(container)
}
