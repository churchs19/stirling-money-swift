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
- **CSV export** of every transaction
- **iCloud sync** of accounts, transactions, categories, budgets and goals across your devices (private database). Categories that two devices both created are merged automatically. Settings such as sort order and the app lock stay per device. *Built but switched off for now; see [iCloud](#icloud-cloudkit).*

Not yet: sharing data with other people.

## Requirements

- Xcode 27 or later
- iOS / iPadOS 27 or later, or macOS 27 or later

## Building and running

Open `Stirling Money.xcodeproj` and run the **Stirling Money** scheme on an iPhone simulator, an iPad, or My Mac.

### Signing

The app and its widget extension share data through the App Group `group.net.s-church.stirlingmoney`, so they need provisioning profiles that include it.
With automatic signing, sign in to Xcode (**Settings → Accounts**) with an account on the project's team. To build under a different team, change the team and bundle identifiers, and the App Group identifier in both entitlements files and in the two copies of `WidgetSnapshot.swift`.

### iCloud (CloudKit)

The app syncs through the CloudKit container `iCloud.net.s-church.stirlingmoney` (private database), using SwiftData's built-in CloudKit support.

**Sync is currently switched off.** Free personal development teams can't have the iCloud or push notification capabilities, so the entitlements are left out and `SyncMonitor.isEnabled` is `false`. To turn sync on with a paid Apple Developer Program team:

1. In Xcode, select the team under Signing & Capabilities.
2. Add the **iCloud** capability with **CloudKit** and the container `iCloud.net.s-church.stirlingmoney`, and the **Push Notifications** capability. (The *Remote notifications* background mode is already set in `Stirling-Money-Info.plist`.)
3. Set `SyncMonitor.isEnabled` to `true` in `Stirling Money/Managers/SyncMonitor.swift`.

Settings → iCloud Sync then shows the account's status instead of "Off".

- **Signing**: the provisioning profile must include the iCloud container and push notifications. Automatic signing adds them once you're signed in to Xcode. If CloudKit can't be set up, the app keeps working with a store on the device only; **Settings → iCloud Sync** shows "Unavailable".
- **Development vs. production**: debug builds use the container's *development* environment, where CloudKit creates the record types and fields automatically as the app saves data.
- **Before an App Store or TestFlight release, deploy the schema to production** in the [CloudKit Console](https://icloud.developer.apple.com/) (your container → Schema → Deploy Schema Changes). Without this, sync quietly does nothing for real users.
- **The production schema can only grow.** Once deployed, record types and fields can't be renamed, removed, or change type. After a release, change the SwiftData models in `Stirling Money/Models` only by **adding** properties, each with a default value or optional, and deploy the schema again before shipping the version that adds them. Never rename or delete a stored property, change its type, or rename a model; add a new property instead and stop using the old one.
- Testing sync needs two devices or simulators signed in to the same iCloud account. Syncing isn't instant; changes usually arrive within seconds to a minute.

### Sample data

In Debug builds, launch with the argument `-UseSampleData` (Product → Scheme → Edit Scheme → Arguments) to use a set of sample accounts, transactions, budgets and goals held in memory. Your real data isn't touched, and nothing syncs.

## Tests

The **Stirling MoneyTests** target uses Swift Testing and covers the money logic: balances, transfers, budget periods and spending, goal progress, report calculations, CSV export, merging duplicate categories, and the widget data. Run them with ⌘U.
Tests use an in-memory store and a fixed UTC calendar, so they don't depend on the machine's time zone.

## Project layout

| Folder | Contents |
|---|---|
| `Stirling Money/Models` | SwiftData models (`Account`, `AccountTransaction`, `Category`, `Budget`, `Goal`) and the logic around them |
| `Stirling Money/Managers` | `Ledger` (creating and editing transactions and transfers), the app lock, the widget snapshot writer |
| `Stirling Money/Views` | Screens, `Reports/` and `Components/` |
| `Stirling Money/Extensions` | Money formatting and parsing, chart colors, macOS-safe view helpers |
| `StirlingMoneyWidgets` | The widget extension |
| `Stirling MoneyTests` | Unit tests |
| `docs` | The re-implementation plan |

[`CLAUDE.md`](CLAUDE.md) has the conventions for working in the code: relationship and delete rules, money as `Decimal`, the macOS rules, and how the widgets get their data.
