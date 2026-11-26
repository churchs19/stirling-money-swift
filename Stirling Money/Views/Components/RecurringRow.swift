import SwiftData
import SwiftUI

/// One recurring transaction: who it's for, its schedule and next date (or why it stopped), and the amount it adds
/// to `account`'s balance each time.
struct RecurringRow: View {
    let rule: RecurringTransaction
    /// The account it's shown in; a transfer reads differently in the account it goes to.
    let account: Account?
    /// Show the account's name (on the all-accounts Recurring screen).
    var showsAccount = false
    @Environment(\.appAccent) private var accent

    private var details: Text {
        if let problem = rule.problem {
            return Text(problem).foregroundStyle(.red)
        }
        if rule.hasEnded() {
            return Text("\(rule.schedule.summary()) · Ended")
        }
        let next = rule.nextDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return Text("\(rule.schedule.summary()) · Next \(next)")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: rule.problem == nil ? "repeat" : "exclamationmark.triangle")
                .foregroundStyle(rule.problem == nil ? accent : .red)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayPayee(in: account))
                    .lineLimit(1)
                details
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if showsAccount, let name = rule.account?.name {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            AmountText(rule.signedAmount(in: account))
        }
        .opacity(rule.hasEnded() ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Edit, Skip Next, Add Now and Delete for a recurring transaction's row, as swipes and a context menu. None of
    /// them in a View Only book (`canEdit` false).
    func recurringRowActions(
        _ rule: RecurringTransaction,
        context: ModelContext,
        canEdit: Bool = true,
        edit: @escaping @MainActor () -> Void
    ) -> some View {
        let canAdd = canEdit && rule.problem == nil && !rule.hasEnded()
        return contentShape(Rectangle())
            .onTapGesture {
                if canEdit {
                    edit()
                }
            }
            .accessibilityAction(named: "Edit") {
                if canEdit {
                    edit()
                }
            }
            .swipeActions(edge: .leading) {
                if canAdd {
                    Button("Skip Next", systemImage: "forward") {
                        withAnimation { RecurringScheduler.skipNext(rule) }
                    }
                    .tint(.orange)
                    Button("Add Now", systemImage: "plus.circle") {
                        withAnimation { _ = RecurringScheduler.addNow(rule, in: context) }
                    }
                    .tint(.green)
                }
            }
            .swipeActions(edge: .trailing) {
                if canEdit {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        withAnimation { context.delete(rule) }
                    }
                }
            }
            .contextMenu {
                if canEdit {
                    Button("Edit…", systemImage: "pencil") {
                        afterMenuCloses(edit)
                    }
                }
                if canAdd {
                    Button("Skip Next", systemImage: "forward") {
                        RecurringScheduler.skipNext(rule)
                    }
                    Button("Add Now", systemImage: "plus.circle") {
                        _ = RecurringScheduler.addNow(rule, in: context)
                    }
                }
                if canEdit {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        context.delete(rule)
                    }
                }
            }
    }
}

#Preview {
    let container = ModelContainer.preview
    let rules = try! container.mainContext.fetch(FetchDescriptor<RecurringTransaction>())
    return List(rules) { RecurringRow(rule: $0, account: $0.account, showsAccount: true) }
        .modelContainer(container)
}
