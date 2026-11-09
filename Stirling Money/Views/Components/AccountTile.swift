import SwiftData
import SwiftUI

/// A square tile for one account: its icon (if any), name and balance.
struct AccountTile: View {
    let account: Account

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Fills the space above the name and balance, with the icon centered in it.
            // Without an icon, the name and balance still sit at the bottom.
            Group {
                if let iconName = account.iconName {
                    AccountIconView(iconName: iconName, textStyle: .largeTitle, isLarge: true)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(account.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            AmountText(account.balance)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .aspectRatio(1, contentMode: .fit)
        // The same colors as the list's rows, so switching layouts doesn't change the color scheme.
        .background(Color.groupedItemBackground, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
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
