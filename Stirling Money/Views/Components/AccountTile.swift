import SwiftData
import SwiftUI

/// A square tile for one account, laid out like the Balance widget: the name, the icon (if any)
/// large and centered, then the balance and the posted balance.
struct AccountTile: View {
    let account: Account

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(account.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            // Fills the space between the name and the balance, with the icon centered in it.
            // Without an icon, the name stays at the top and the balances at the bottom.
            Group {
                if let iconName = account.iconName {
                    AccountIconView(iconName: iconName, textStyle: .largeTitle, isLarge: true)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            AmountText(account.balance)
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("Posted \(account.postedBalance, format: .localCurrency)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .aspectRatio(1, contentMode: .fit)
        // The same colors as the list's rows, so switching layouts doesn't change the color scheme.
        .background(Color.groupedItemBackground, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let container = ModelContainer.preview
    let accounts = try! container.mainContext.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)]))
    return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
        ForEach(accounts) { AccountTile(account: $0) }
    }
    .padding()
    .modelContainer(container)
}
