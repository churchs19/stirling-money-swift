# Stirling Money

A personal checkbook and budgeting app for iPhone, iPad and Mac, built with SwiftUI and SwiftData.

It's a re-implementation of [Stirling Money for Windows Phone](https://github.com/churchs19/stirlingmoney).
[`docs/PLAN.md`](docs/PLAN.md) maps the original app's features to this one and records the decisions made along the way.

## Features

- **Accounts and register**: balances (available and posted), the total across accounts, and a searchable list of transactions you can mark as posted
- **Transactions**: withdrawals, deposits, checks (numbered automatically) and transfers between accounts, kept as linked pairs
- **Categories**: assign while entering a transaction, or manage them on their own screen
- **Budgets**: weekly, monthly, yearly or custom periods, for one category or all spending
- **Goals**: savings targets measured against an account's balance, with days left
- **Reports** (Swift Charts): net income, spending by category, one category over time, budget history
- **Widgets**: an account's balance (or the total) and a goal's progress; tapping an account's widget opens its transactions
- **App lock**: Face ID, Touch ID or the device passcode
- **Account tiles** (or a list) with an optional icon: an SF Symbol or one of 116 payment logos and currency signs
- **Accent color**: Stirling Money's purple, one you pick, or (on the Mac) the system's
- **CSV export** of every transaction

Not yet: iCloud sync and sharing data with other people. Both are deferred; the data model is kept CloudKit-compatible so sync can be added without a migration.

## Requirements

- Xcode 27 or later
- iOS / iPadOS 27 or later, or macOS 27 or later

## Building and running

Open `Stirling Money.xcodeproj` and run the **Stirling Money** scheme on an iPhone simulator, an iPad, or My Mac.

### Signing

The app and its widget extension share data through the App Group `group.net.s-church.stirlingmoney`, so they need provisioning profiles that include it.
With automatic signing, sign in to Xcode (**Settings → Accounts**) with an account on the project's team. To build under a different team, change the team and bundle identifiers, and the App Group identifier in both entitlements files and in the two copies of `WidgetSnapshot.swift`.

### Sample data

In Debug builds, launch with the argument `-UseSampleData` (Product → Scheme → Edit Scheme → Arguments) to use a set of sample accounts, transactions, budgets and goals held in memory. Your real data isn't touched.

## Tests

The **Stirling MoneyTests** target uses Swift Testing and covers the money logic: balances, transfers, budget periods and spending, goal progress, report calculations, CSV export, and the widget data. Run them with ⌘U.
Tests use an in-memory store and a fixed UTC calendar, so they don't depend on the machine's time zone.

## Project layout

| Folder | Contents |
|---|---|
| `Stirling Money/Models` | SwiftData models (`Account`, `AccountTransaction`, `Category`, `Budget`, `Goal`) and the logic around them |
| `Stirling Money/Managers` | `Ledger` (creating and editing transactions and transfers), the app lock, the widget snapshot writer |
| `Stirling Money/Views` | Screens, `Reports/` and `Components/` |
| `Stirling Money/Extensions` | Money formatting and parsing, chart colors, macOS-safe view helpers |
| `Shared` | Code used by the app, the widgets and the Watch targets (the widget summary) |
| `StirlingMoneyWidgets` | The widget extension |
| `StirlingMoney Watch App`, `StirlingMoneyWatchWidgets` | The Apple Watch app and its complications (in progress) |
| `Stirling MoneyTests` | Unit tests |
| `docs` | The re-implementation plan |

[`CLAUDE.md`](CLAUDE.md) has the conventions for working in the code: relationship and delete rules, money as `Decimal`, the macOS rules, and how the widgets get their data.

## Acknowledgements

Account icons include the payment and currency glyphs of [PaymentFont](https://github.com/AlexanderPoellmann/PaymentFont) by Alexander Manfred Pöllmann, used under the MIT License (included at `Stirling Money/Resources/Fonts/PaymentFont-LICENSE.txt`). Brand logos are trademarks of their owners.
