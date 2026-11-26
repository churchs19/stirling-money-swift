import SwiftUI

/// The total, then each account with its icon and balance. Tapping one shows its posted balance.
struct AccountsPage: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        List {
            if snapshot.accounts.isEmpty {
                Text("Add an account in Stirling Money on your iPhone.")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    LabeledContent("Total") {
                        BalanceText(amount: snapshot.total)
                    }
                    .font(.headline)
                } header: {
                    BookHeader()
                }

                Section {
                    ForEach(snapshot.accounts) { account in
                        NavigationLink(value: account) {
                            AccountRow(account: account)
                        }
                    }
                } footer: {
                    UpdatedFooter()
                }
            }
        }
        .navigationTitle("Accounts")
    }
}

private struct AccountRow: View {
    let account: WidgetSnapshot.AccountSummary

    var body: some View {
        HStack(spacing: 8) {
            if SummaryAccountIcon.hasIcon(account) {
                SummaryAccountIcon(account: account, size: 15)
                    .foregroundStyle(.tint)
                    .frame(width: 30)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .lineLimit(2)
                BalanceText(amount: account.balance)
                    .font(.headline)
            }
        }
    }
}

/// One account: its icon, its balance and its posted balance.
struct AccountDetailView: View {
    let account: WidgetSnapshot.AccountSummary

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if SummaryAccountIcon.hasIcon(account) {
                    SummaryAccountIcon(account: account, size: 30)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                BalanceText(amount: account.balance)
                    .font(.title2.bold())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("Posted \(account.postedBalance, format: .localCurrency)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                UpdatedFooter()
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(account.name)
    }
}

/// A balance in local currency, red when negative.
struct BalanceText: View {
    let amount: Decimal

    var body: some View {
        Text(amount, format: .localCurrency)
            .monospacedDigit()
            .foregroundStyle(amount < 0 ? .red : .primary)
    }
}

#Preview {
    NavigationStack {
        AccountsPage(snapshot: .sample)
    }
    .environment(WatchStore(fileURL: nil, snapshot: .sample))
}
