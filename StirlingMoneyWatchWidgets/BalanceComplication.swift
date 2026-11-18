import SwiftUI
import WidgetKit

struct BalanceComplicationEntry: TimelineEntry {
    let date: Date
    /// nil when there's no summary yet or the chosen account was deleted; `isMissing` says which.
    let content: Content?
    var accent: Color = Color("AccentColor")
    /// The chosen account was deleted.
    var isMissing = false

    struct Content {
        /// nil for the total of all accounts.
        let account: WidgetSnapshot.AccountSummary?
        let name: String
        let balance: Decimal
        let accountCount: Int
    }
}

struct BalanceComplicationProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BalanceComplicationEntry {
        entry(for: SelectAccountIntent(), snapshot: .sample)
    }

    func snapshot(for configuration: SelectAccountIntent, in context: Context) async -> BalanceComplicationEntry {
        entry(for: configuration, snapshot: WidgetSnapshot.load() ?? (context.isPreview ? .sample : nil))
    }

    func timeline(for configuration: SelectAccountIntent, in context: Context) async -> Timeline<BalanceComplicationEntry> {
        // The Watch app reloads complications whenever a new summary arrives.
        Timeline(entries: [entry(for: configuration, snapshot: WidgetSnapshot.load())], policy: .never)
    }

    /// The watch face editor lists these: the total, then each account.
    func recommendations() -> [AppIntentRecommendation<SelectAccountIntent>] {
        var recommendations = [AppIntentRecommendation(intent: SelectAccountIntent(), description: "All Accounts")]
        for account in WidgetSnapshot.load()?.accounts ?? [] {
            let intent = SelectAccountIntent()
            intent.account = AccountEntity(id: account.id, name: account.name)
            recommendations.append(AppIntentRecommendation(intent: intent, description: Text(account.name)))
        }
        return recommendations
    }

    private func entry(for configuration: SelectAccountIntent, snapshot: WidgetSnapshot?) -> BalanceComplicationEntry {
        let accent = complicationAccent(snapshot)
        let content: BalanceComplicationEntry.Content?
        let choice = BalanceChoice.choose(accountID: configuration.account?.id, in: snapshot)
        switch choice {
        case .total:
            content = snapshot.map {
                BalanceComplicationEntry.Content(
                    account: nil, name: String(localized: "All Accounts"),
                    balance: $0.total, accountCount: $0.accounts.count
                )
            }
        case let .account(account):
            content = BalanceComplicationEntry.Content(
                account: account, name: account.name, balance: account.balance, accountCount: 1
            )
        case .noSummary, .missing:
            content = nil
        }
        return BalanceComplicationEntry(date: .now, content: content, accent: accent, isMissing: choice == .missing)
    }
}

struct BalanceComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BalanceComplicationEntry

    var body: some View {
        if let content = entry.content {
            switch family {
            case .accessoryCircular:
                circular(content)
            case .accessoryCorner:
                icon(content, size: 20)
                    .widgetLabel {
                        Text(content.balance, format: .localCurrency.notation(.compactName))
                    }
            case .accessoryInline:
                Text("\(content.name) \(content.balance, format: .localCurrency)")
            default:
                rectangular(content)
            }
        } else if entry.isMissing {
            ComplicationMessage(
                inline: "Account deleted",
                message: "This account was deleted. Edit the watch face to choose another.",
                systemImage: "banknote"
            )
        } else {
            ComplicationMessage(inline: "Stirling Money", message: "Open Stirling Money on your iPhone.", systemImage: "banknote")
        }
    }

    private func circular(_ content: BalanceComplicationEntry.Content) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                icon(content, size: 14)
                Text(content.balance, format: .localCurrency.notation(.compactName))
                    .font(.system(size: 12, weight: .semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding(4)
        }
    }

    private func rectangular(_ content: BalanceComplicationEntry.Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if let account = content.account, SummaryAccountIcon.hasIcon(account) {
                    SummaryAccountIcon(account: account, size: 12)
                        .foregroundStyle(entry.accent)
                        .widgetAccentable()
                }
                Text(content.name)
                    .font(.headline)
                    .foregroundStyle(entry.accent)
                    .widgetAccentable()
                    .lineLimit(1)
            }
            Text(content.balance, format: .localCurrency)
                .font(.title3.bold())
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(content.balance < 0 ? .red : .primary)
            Group {
                if let account = content.account {
                    Text("Posted \(account.postedBalance, format: .localCurrency)")
                } else {
                    Text("^[\(content.accountCount) account](inflect: true)")
                }
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The account's icon, or a banknote for the total and for accounts without one.
    @ViewBuilder
    private func icon(_ content: BalanceComplicationEntry.Content, size: CGFloat) -> some View {
        Group {
            if let account = content.account, SummaryAccountIcon.hasIcon(account) {
                SummaryAccountIcon(account: account, size: size)
            } else {
                Image(systemName: "banknote")
                    .font(.system(size: size))
            }
        }
        .foregroundStyle(entry.accent)
        .widgetAccentable()
    }
}

struct BalanceComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WatchBalance", intent: SelectAccountIntent.self, provider: BalanceComplicationProvider()) { entry in
            BalanceComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Balance")
        .description("An account's balance, or the total of all your accounts.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    BalanceComplication()
} timeline: {
    BalanceComplicationEntry(date: .now, content: .init(
        account: WidgetSnapshot.sample.accounts[0], name: "Checking", balance: 1250.75, accountCount: 1
    ))
    BalanceComplicationEntry(date: .now, content: .init(account: nil, name: "All Accounts", balance: 9750.75, accountCount: 2))
    BalanceComplicationEntry(date: .now, content: nil)
    BalanceComplicationEntry(date: .now, content: nil, isMissing: true)
}

#Preview("Circular", as: .accessoryCircular) {
    BalanceComplication()
} timeline: {
    BalanceComplicationEntry(date: .now, content: .init(
        account: WidgetSnapshot.sample.accounts[0], name: "Checking", balance: 1250.75, accountCount: 1
    ))
}
