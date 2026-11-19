import SwiftData
import SwiftUI

/// One register line: a posted toggle, payee with date and details, and the signed amount.
struct TransactionRow: View {
    let transaction: AccountTransaction

    private var details: String {
        var parts = [transaction.date.formatted(date: .abbreviated, time: .omitted)]
        if let checkNumber = transaction.checkNumber {
            // Check numbers are identifiers, so no grouping separators ("1001", not "1,001").
            let number = checkNumber.formatted(.number.grouping(.never))
            parts.append(String(localized: "Check \(number)"))
        }
        if let category = transaction.category {
            parts.append(category.name)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                transaction.isPosted.toggle()
            } label: {
                PostedCheckmark(isPosted: transaction.isPosted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(transaction.isPosted ? "Posted" : "Not posted")
            .accessibilityHint("Toggles whether the transaction has cleared the bank")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(transaction.displayPayee)
                        .lineLimit(1)
                    if transaction.recurrence != nil {
                        Image(systemName: "repeat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Recurring")
                    }
                }
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            AmountText(transaction.amount)
        }
    }
}

#Preview {
    let container = ModelContainer.preview
    let transactions = try! container.mainContext.fetch(FetchDescriptor<AccountTransaction>())
    return List(transactions) { TransactionRow(transaction: $0) }
        .modelContainer(container)
}
