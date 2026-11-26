# Stirling Money

A personal checkbook and budgeting app for iPhone, iPad and Mac, built with SwiftUI and SwiftData.

It's a re-implementation of [Stirling Money for Windows Phone](https://github.com/churchs19/stirlingmoney).
[`docs/PLAN.md`](docs/PLAN.md) maps the original app's features to this one and records the decisions made along the way.

## Features

- **Books**: separate sets of accounts, categories, budgets and goals (household and personal, say), switched from the books menu on every tab. Everything else in the app (totals, reports, widgets, the Watch, CSV export) is for the current book
- **iCloud sync**: every book syncs across your devices signed in to the same Apple ID, with changes merged field by field when two devices edit the same thing. Settings → iCloud shows the status and has Sync Now
- **Sharing**: share a book with other Apple IDs from the books menu, choosing for each person Can Make Changes or View Only. They tap the invitation to add the book; the owner can manage people or stop sharing, and anyone can leave
- **Accounts and register**: balances (available and posted), the total across accounts, and a searchable list of transactions you can mark as posted
- **Transactions**: withdrawals, deposits, checks (numbered automatically) and transfers between accounts, kept as linked pairs
- **Categories**: assign while entering a transaction, or manage them on their own screen
- **Budgets**: weekly, monthly, yearly or custom periods, for one category or all spending
- **Goals**: savings targets measured against an account's balance, with days left
- **Reports** (Swift Charts): net income, spending by category, one category over time, budget history
- **Recurring transactions**: rent, pay, subscriptions and regular transfers, weekly, monthly, twice a month or yearly. They're added on schedule as unposted transactions (in the background on iPhone and iPad when iOS allows, otherwise when the app opens), and the widgets and Watch count them from the day they fall due. Manage them in each account's Upcoming section or the Recurring screen
- **Widgets**: an account's balance (or the total), a goal's progress, one budget's spending (also on the iPhone Lock Screen) and All Budgets; tapping an account's widget opens its transactions, a budget widget opens Budgets
- **Apple Watch** (read-only): accounts, budgets and goals, plus Balance (the total or one account), Goal and Budget complications, chosen when you edit a watch face. The iPhone sends the Watch a summary whenever something changes
- **App lock**: Face ID, Touch ID or the device passcode
- **Account tiles** (or a list) with an optional icon: an SF Symbol or one of 116 payment logos and currency signs
- **Accent color**: Stirling Money's purple, one you pick, or (on the Mac) the system's
- **CSV export** of the current book's transactions

## Requirements

- Xcode 27 or later
- iOS / iPadOS 27 or later, or macOS 27 or later
- watchOS 27.2 or later for the Watch app

## Building and running

Open `Stirling Money.xcodeproj` and run the **Stirling Money** scheme on an iPhone simulator, an iPad, or My Mac.
The Watch app is embedded in the iPhone app: run the **StirlingMoney Watch App** scheme on a Watch simulator paired with the iPhone simulator, or install the iPhone app on a phone and the Watch app installs from it.

### Signing

The app and its widget extension share data through the App Group `group.net.s-church.stirlingmoney`, and so do the Watch app and its complications (in a separate container on the Watch), so all four need provisioning profiles that include it.
With automatic signing, sign in to Xcode (**Settings → Accounts**) with an account on the project's team. To build under a different team, change the team and bundle identifiers, and the App Group identifier in the four entitlements files and in `Shared/WidgetSnapshot.swift`.

The app target also has the **iCloud** capability (CloudKit, container `iCloud.net.s-church.stirlingmoney`), **Push Notifications**, and the Remote notifications background mode, for sync; the team needs a paid developer account.

To install on a real Apple Watch, Xcode has to see the Watch (paired with a connected iPhone, unlocked, Developer Mode on) so it can register it with the team; otherwise the Watch refuses the app.

### Background refresh

Recurring transactions are added in the background through `BGTaskScheduler` (`net.s-church.stirlingmoney.recurring`, listed in `Stirling-Money-Info.plist`, with the Background fetch mode). iOS decides when that runs; the simulator never does. To trigger it on a device, pause the app in Xcode's debugger and run:

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"net.s-church.stirlingmoney.recurring"]
```

### iCloud and the CloudKit schema

Sync is the app's own, built on `CKSyncEngine` (SwiftData's built-in CloudKit mirroring is turned off with `cloudKitDatabase: .none`, since it has no shared database). Each book is a CloudKit zone; sharing one is a zone-wide `CKShare`. Values are stored in encrypted fields, money as exact decimal strings. The details are in `CLAUDE.md` and Phase 11 of the plan.

- **Development builds** use the CloudKit development environment, where record types and fields are created as the app first saves them.
- **Before any TestFlight or App Store build**, deploy the schema to production: in the [CloudKit Console](https://icloud.developer.apple.com), choose the container, then **Schema → Deploy Schema Changes…** and deploy from Development to Production. Production builds can only use what's been deployed.
- **After that, only add**: new record types and fields are fine (deploy again), but never rename or delete one, and never change a field's type; devices on older versions still use them.
- **Testing sharing** needs a second Apple ID, on another device or a simulator signed in to it. Open the invitation link through the system (a tap in Messages or Mail, or `xcrun simctl openurl`), not by pasting it into Safari.
- Sync never runs with `-UseSampleData` or `-UITesting`, or while hosting unit tests, so sample data never reaches iCloud.

### Sample data

In Debug builds, launch with the argument `-UseSampleData` (Product → Scheme → Edit Scheme → Arguments) to use a set of sample accounts, transactions, budgets and goals held in memory. Your real data isn't touched.
The Watch app takes `-UseSampleData` too: it shows a built-in sample summary and doesn't contact the iPhone.
`-UITesting` (used by the UI tests) also uses the sample data, and keeps settings in a store of its own that starts empty.

## Tests

| Target | What it covers | Run on |
|---|---|---|
| **Stirling MoneyTests** (Swift Testing, about 270 tests) | The money logic: balances, transfers, budget periods and spending, goals, reports, recurring transactions, CSV export, the forms, amounts in other locales, the app lock, the widget and Watch summary, widget pickers and links; books; sync with a fake CloudKit server and two simulated devices (record mapping, conflicts, deletes, sharing, View Only, merging categories, account changes) | An iPhone simulator (⌘U with the **Stirling Money** scheme) |
| **Stirling MoneyUITests** (17 tests + launch time, about 7 minutes) | End to end with the sample data: accounts and total, adding an account, a withdrawal and a transfer, search, marking posted, adding a budget and a goal, recurring transactions, every report, layout, accent color, switching and adding books, a View Only book | An iPhone simulator |
| **StirlingMoney Watch AppTests** | How the Watch takes in summaries from the iPhone | A Watch simulator (**StirlingMoney Watch App** scheme) |
| **StirlingMoney Watch AppUITests** | The Watch's Accounts, Budgets and Goals pages with sample data | A Watch simulator |

Unit tests use an in-memory store and a fixed UTC calendar, so they don't depend on the machine's time zone. When the app hosts them it uses an empty in-memory store and leaves your data, the widgets and the Watch alone.
The iPhone UI tests launch the app with `-UITesting`, which uses the sample data and starts with fresh settings without touching yours.

## Project layout

| Folder | Contents |
|---|---|
| `Stirling Money/Models` | SwiftData models (`Book`, `Account`, `AccountTransaction`, `Category`, `Budget`, `Goal`, `RecurringTransaction`) and the logic around them |
| `Stirling Money/Managers` | `Ledger` (creating and editing transactions and transfers), `Books`, `CategoryMerger`, the app lock, the widget snapshot writer, `WatchSync` (sending the summary to the Watch), `RecurringScheduler` and `RecurringRunner` (adding recurring transactions when they fall due) |
| `Stirling Money/Managers/Sync` | iCloud sync and sharing: each model as a CloudKit record, the importer and conflict merger, `SyncProcessor` (testable without CloudKit) and `SyncCoordinator` (the two `CKSyncEngine`s) |
| `Stirling Money/Views` | Screens, `Reports/` and `Components/` |
| `Stirling Money/Extensions` | Money formatting and parsing, chart colors, macOS-safe view helpers |
| `Shared` | Code and resources used by the app, the widgets and the Watch targets: the summary and its projection of upcoming recurring transactions, the budget card, the widget pickers, the currency format, PaymentFont |
| `StirlingMoneyWidgets` | The widget extension: Balance, Goal, Budget and All Budgets |
| `StirlingMoney Watch App`, `StirlingMoneyWatchWidgets` | The Apple Watch app and its complications |
| `Stirling MoneyTests`, `StirlingMoney Watch AppTests` | Unit tests |
| `Stirling MoneyUITests`, `StirlingMoney Watch AppUITests` | UI tests |
| `docs` | The re-implementation plan |

[`CLAUDE.md`](CLAUDE.md) has the conventions for working in the code: relationship and delete rules, money as `Decimal`, books and View Only, the macOS rules, how the widgets and the Watch get their data, and how sync works.

## Acknowledgements

Account icons include the payment and currency glyphs of [PaymentFont](https://github.com/AlexanderPoellmann/PaymentFont) by Alexander Manfred Pöllmann, used under the MIT License (included at `Shared/Fonts/PaymentFont-LICENSE.txt`). Brand logos are trademarks of their owners.
