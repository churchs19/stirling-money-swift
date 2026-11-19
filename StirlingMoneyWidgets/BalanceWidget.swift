import SwiftUI
import WidgetKit

struct BalanceEntry: TimelineEntry {
    let date: Date
    /// nil when the app hasn't written any data yet.
    let snapshot: WidgetSnapshot?
    /// nil means the total of all accounts.
    let account: WidgetSnapshot.AccountSummary?
    /// The configured account no longer exists.
    let isMissing: Bool
    /// The accent color chosen in the app, for the account's icon.
    var accent: Color = WidgetAccent.standard
}

struct BalanceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BalanceEntry {
        BalanceEntry(date: .now, snapshot: .sample, account: WidgetSnapshot.sample.accounts.first, isMissing: false, accent: WidgetAccent.current)
    }

    func snapshot(for configuration: SelectAccountIntent, in context: Context) async -> BalanceEntry {
        if context.isPreview, WidgetSnapshot.load() == nil {
            return placeholder(in: context)
        }
        return entry(for: configuration, snapshot: WidgetSnapshot.load()?.projected(on: .now), on: .now)
    }

    func timeline(for configuration: SelectAccountIntent, in context: Context) async -> Timeline<BalanceEntry> {
        // The app reloads widgets when it writes new data. Until then, recurring transactions that fall due
        // change the balance at the start of their day.
        let summary = WidgetSnapshot.load()
        let dates = summary?.timelineDates(now: .now) ?? [.now]
        let entries = dates.map { entry(for: configuration, snapshot: summary?.projected(on: $0), on: $0) }
        return Timeline(entries: entries, policy: dates.count > 1 ? .atEnd : .never)
    }

    private func entry(for configuration: SelectAccountIntent, snapshot: WidgetSnapshot?, on date: Date) -> BalanceEntry {
        let choice = BalanceChoice.choose(accountID: configuration.account?.id, in: snapshot)
        var account: WidgetSnapshot.AccountSummary?
        if case let .account(chosen) = choice {
            account = chosen
        }
        return BalanceEntry(date: date, snapshot: snapshot, account: account, isMissing: choice == .missing, accent: WidgetAccent.current)
    }
}

struct BalanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BalanceEntry

    var body: some View {
        if let snapshot = entry.snapshot, !entry.isMissing {
            content(snapshot: snapshot)
                // A chosen account opens its transactions; "All Accounts" opens the app as usual.
                .widgetURL(entry.account.map { Self.url(forAccountID: $0.id) })
        } else {
            WidgetMessage(text: entry.isMissing ? "This account was deleted. Edit the widget to choose another." : "Open Stirling Money to see your balances.")
        }
    }

    /// The app's link to an account's register. Matches `DeepLink` in the app; keep them in step.
    static func url(forAccountID id: String) -> URL {
        var components = URLComponents()
        components.scheme = "stirlingmoney"
        components.host = "account"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url!
    }

    @ViewBuilder
    private func content(snapshot: WidgetSnapshot) -> some View {
        let name = entry.account?.name ?? String(localized: "All Accounts")
        let balance = entry.account?.balance ?? snapshot.total

        switch family {
        #if os(iOS)
            case .accessoryInline:
                Text("\(name) \(balance, format: .localCurrency)")
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Text(name).font(.headline).widgetAccentable()
                    Text(balance, format: .localCurrency)
                    if let account = entry.account {
                        Text("Posted \(account.postedBalance, format: .localCurrency)")
                            .foregroundStyle(.secondary)
                    }
                }
        #endif
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                if let account = entry.account, SummaryAccountIcon.hasIcon(account) {
                    SummaryAccountIcon(account: account)
                        .foregroundStyle(entry.accent)
                        // In tinted and clear Home Screen styles, the icon takes the system's tint instead.
                        .widgetAccentable()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Spacer(minLength: 0)
                }
                Text(balance, format: .localCurrency)
                    .font(.title2.bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(balance < 0 ? .red : .primary)
                if let account = entry.account {
                    Text("Posted \(account.postedBalance, format: .localCurrency)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("^[\(snapshot.accounts.count) account](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct BalanceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Balance", intent: SelectAccountIntent.self, provider: BalanceProvider()) { entry in
            BalanceWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Balance")
        .description("An account's balance, or the total of all your accounts.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
            [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline]
        #else
            [.systemSmall, .systemMedium]
        #endif
    }
}

/// Shown when there's nothing to display yet.
struct WidgetMessage: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#Preview("Account", as: .systemSmall) {
    BalanceWidget()
} timeline: {
    BalanceEntry(date: .now, snapshot: .sample, account: WidgetSnapshot.sample.accounts[0], isMissing: false)
    BalanceEntry(
        date: .now, snapshot: .sample,
        account: .init(id: "card", name: "Credit Card", balance: -1068.38, postedBalance: -900, iconGlyph: "\u{F045}"),
        isMissing: false
    )
    BalanceEntry(date: .now, snapshot: .sample, account: nil, isMissing: false)
    BalanceEntry(date: .now, snapshot: nil, account: nil, isMissing: false)
}
