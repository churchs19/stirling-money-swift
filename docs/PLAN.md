# Stirling Money: re-implementation plan

This app re-implements the features of the original Stirling Money, a Windows Phone 8 app written in C#
([churchs19/stirlingmoney](https://github.com/churchs19/stirlingmoney), last changed January 2017),
as a SwiftUI + SwiftData app for iOS, iPadOS and macOS.

## Status

| Phase | Scope | Status |
|---|---|---|
| 1 | Data model and calculations | Done (`b81a15e`) |
| 2 | Accounts list and account register | Done (`fad2bcf`) |
| 3 | Entering and editing transactions; categories | Done (`a87cf70`) |
| 4 | Budgets and goals | Done (`368965c`) |
| 5 | Reports | Done (`0a38edc`) |
| 6 | Platform features (widgets, app lock, export, settings) | Done; sync still deferred |

## Decisions

| Question | Decision |
|---|---|
| Platforms | iOS, iPadOS and macOS from one multiplatform target. visionOS is also listed in the target but hasn't been built or tested. |
| CloudKit sync | **Deferred.** Models are kept CloudKit-compatible (every property has a default or is optional, every relationship is optional, no unique constraints) so sync can be turned on later without a migration. |
| Sharing data with other people | **Deferred.** The old app's "authorized users" would need CloudKit sharing (`CKShare`), which SwiftData doesn't support well. |
| Importing old app data | **Not needed.** No importer will be built. |
| Ads, analytics, trial licensing | Dropped. |

## The original app

### Data model

| Entity | Fields | Logic that depends on it |
|---|---|---|
| Account | name, initial balance, image | Balance = initial balance + all transactions. Posted balance = initial balance + posted transactions only. Count of transactions, used for sorting. |
| Transaction | date, amount (signed), location (payee), note, posted flag, check number, account, category | |
| Category | name | Created on the fly when a new name is typed while entering a transaction. |
| Budget | name, amount, optional category, period (weekly/monthly/yearly/custom), start date, optional end date | Start and end of the current period. Amount spent in the period, for one category or all. |
| Goal | name, target amount, account, initial balance, start date, target date | Amount left, days left or overdue, progress. |

### Features

1. Home screen with Accounts, Budgets and Goals tabs, and a total balance across all accounts.
2. Account register: transactions loaded 40 at a time, available and posted balances, marking transactions posted inline, search, edit and delete.
3. Four ways to enter a transaction:
   - Withdrawal and deposit, with the sign applied automatically.
   - Check, with the number defaulting to the account's highest check number + 1.
   - Transfer, which creates two linked entries ("Transfer to X" and "Transfer from Y").
   - Validation: a payee is required, or for a transfer, a destination account.
4. Categories screen: list, add, edit and delete.
5. Budgets and goals: add/edit screens and summary cards on the home screen.
6. Reports, all leaving out transfers:
   - Budget history: spent vs. budget for the last 7 periods.
   - Spending by category: pie chart of the top 9 categories plus "Other", over N months.
   - One category over time: monthly bars.
   - Net income: income vs. expenses per month.
7. Settings: account sort order (alphabetical or most used), app password, sync on/off and sync on startup, authorized users.
8. Platform features: Live Tiles per account and goal, SkyDrive backup and restore, Azure Mobile Services sync with a Microsoft account, about page, rate the app, ads, analytics, trial licensing, and strings in 44 languages.

### Old behavior deliberately not copied

- **Transfers were identified by matching translated text** ("Transfer to"/"Transfer from" in the payee), so a payee containing those words broke reports and edits. Transfers are now an explicit kind with the two halves linked by a relationship, and the label is built from the other account's name when shown.
- **Money was stored as `double`.** It's now `Decimal`.
- **The current-period date math had bugs.** The February check never matched (`start.Month > 28`), weekly budgets used the monthly logic, and the budget end date was ignored. Rewritten with month-end and leap-year tests.
- **Search was never finished** (the SQLite search threw `NotImplementedException`). Implemented in Phase 2.
- **The app password was stored in plain text.** To be replaced with Face ID or the device passcode.
- **Every money calculation scanned the repository.** SwiftData relationships and computed properties replace that layer.

## Phases

### Phase 1: Data model (done)

- [x] `Account`, `AccountTransaction`, `Category`, `Budget` and `Goal` models; `TransactionKind` and `BudgetPeriod` enums
- [x] Relationships and delete rules (documented in `CLAUDE.md`)
- [x] `Ledger` for creating transactions with the right sign, creating and deleting transfer pairs, and finding or creating categories
- [x] Budget period math, amount spent, goal progress, with unit tests
- [x] Remove the template `Item` model

Choices made that differ from the old app:
- Category budgets subtract refunds; "all spending" budgets count only money going out. The old app counted income as negative spending.
- Deleting a category deletes its budgets, rather than silently turning them into all-spending budgets. Open to changing.
- The transaction model is named `AccountTransaction` to avoid clashing with SwiftUI's `Transaction`.

### Phase 2: Accounts and register (done)

- [x] Accounts list with balances, a total, and sorting by name or most used (remembered between launches)
- [x] Confirmation before deleting an account, saying how many transactions and goals go with it
- [x] Account register: available and posted balances, newest first, posted toggle, swipe and right-click actions, search by payee, note, category or check number
- [x] Edit Account sheet
- [x] Transfers whose other account was deleted read "Transfer from a deleted account"; the remaining account's balance is unchanged
- [x] Builds for macOS: touch-only modifiers go through `View+Platform.swift`; right-click menus for mouse users

### Phase 3: Transaction entry (done)

- [x] One form (`TransactionFormView`) that adapts to the kind: withdrawal, deposit, check or transfer
- [x] Check number defaults to the account's next check number
- [x] Category picker with "New Category…", which reuses an existing category with the same name
- [x] Transfers: choose the other account; editing one half updates the other's amount, date, note and account
- [x] Validation: amount above zero, payee required (or the other account for a transfer), check number optional but a whole number
- [x] Tap a register row (or right-click → Edit) to edit it; delete from the form with confirmation
- [x] Categories screen (Accounts → ⋯ → Categories): list with usage counts, add, rename (no duplicate names), delete with confirmation

Choices made:
- The form keeps typed text in a `TransactionDraft` and nothing changes until Save, unlike Edit Account, which applies as you type.
- Amounts are typed without a sign; the kind decides it. The amount shows as currency ("$1,450.00") except while it's being edited.
- The Posted control in the form uses the same green check circle as the register (`PostedCheckmark`).
- Changing a transfer to another kind, or the other way round, deletes the old entry (and its other half) and creates a new one.
- Posted status stays separate for each half of a transfer, since each bank clears its side on its own schedule. A new transfer starts with both halves the same.
- Editing a transfer whose other account was deleted, and choosing an account, creates a new other half.
- A transfer's direction can't be flipped while editing; delete it and enter it from the other account.
- A category created from the form stays even if the form is cancelled.

### Phase 4: Budgets and goals (done)

- [x] Budget add/edit: name, amount, category or all spending, weekly/monthly/yearly/custom, start date, optional end date (required for custom)
- [x] Budget cards: spent vs. amount for the current period, amount left or over, the period's dates; "Starts …" or "Ended" outside its dates
- [x] Goal add/edit; the account's balance at creation is the starting point
- [x] Goal cards: amount left or "Reached", days left or overdue, progress
- [x] Home is a `TabView` (Accounts / Budgets / Goals) with `.sidebarAdaptable`: tab bar on iPhone, sidebar on iPad and Mac. Reports joins in Phase 5.

Choices made:
- A new budget starts on the first of the current month.
- When a recurring budget's end date falls mid-period, the last period is cut short at the end date.
- Moving a goal to a different account restarts its progress from that account's balance today. Renaming or changing the target keeps the starting point.
- Budgets and goals delete from a swipe or right-click without asking (they don't own any other data); deleting from the form asks first.
- Goal target dates in the past are allowed; the card shows them as overdue.
- Amount fields share `CurrencyField`, which shows currency except while editing.

### Phase 5: Reports (done)

A Reports tab with four Swift Charts reports. Each has a tap/hover callout and lists its values in a table underneath.

- [x] Budget history: last 7 periods (fewer if the budget is newer), bars with a dashed budget line; the table flags periods over budget
- [x] Spending by category: donut (`SectorMark`), top 7 + Other, total or selected slice in the middle
- [x] One category over time: monthly bars
- [x] Net income: income vs. expenses per month, grouped bars
- [x] 3 / 6 / 12 month picker, shared by the monthly reports and remembered between launches

Choices made:
- **Top 7 + Other instead of 9 + Other.** The chart palette has 8 validated colors, ordered so neighboring colors stay distinct for color-blind readers; a 10th slice would need a made-up color.
- **Category colors don't change with the range.** The 7 named categories are the biggest over all time, so switching 3 → 12 months doesn't repaint the chart. Smaller ones go into Other.
- Uncategorized spending is a slice of its own, not part of Other.
- Category reports count spending less refunds, like category budgets. A month where refunds outweigh spending shows a negative bar.
- The palette (`ChartPalette`) was checked with the data-viz validator against the system list background in light and dark mode. Three light-mode colors are under 3:1 contrast with white, which is why every chart also lists its values as text.

### Phase 6: Platform features (done, except sync and sharing)

- [x] **Widgets**: Balance (one account or the total; small, medium, and Lock Screen on iPhone) and Goal (progress ring, amount to go, days left). Configured with App Intents.
- [x] **App lock**: "Require Face ID" (or Touch ID / passcode) in Settings. Locks at launch and when the app goes to the background; turning it on asks for Face ID first.
- [x] **Export**: every transaction as CSV, via the share sheet (Save to Files on iPhone/iPad).
- [x] **Rate the app**: `RequestReviewAction` in Settings.
- [x] **Settings**: a tab on iPhone/iPad; the Settings window (⌘,) on the Mac.
- [x] **String catalog**: `Localizable.xcstrings`, English only for now.

Choices made:
- **Widgets read a JSON snapshot**, not the SwiftData store: the widget target can't share the model files without per-file membership changes. The app writes it when it goes to the background, so widgets update when you leave the app.
- Tapping a Balance widget set to one account opens that account's register (`widgetURL` → `onOpenURL`, see `DeepLink`); "All Accounts" just opens the app. Confirmed on the simulator; the `stirlingmoney` scheme doesn't need registering in Info.plist for widget links.
- Widget configuration refers to accounts and goals by a stable ID, so renaming keeps the widget pointed at the same one; deleting shows "Edit the widget to choose another."
- **The lock asks once** when the app becomes active; after a cancel you tap Unlock (asking again automatically would loop). If the device's passcode is removed, the lock is skipped rather than shutting you out. On the Mac it locks at launch and when the app is hidden or minimized, not on every app switch.
- **Export uses the share sheet on the Mac too.** The Mac app is sandboxed with read-only access to chosen files, so a Save dialog would need the "User Selected File" setting changed to read/write (a project change).
- Exported amounts use "." as the decimal point and text that looks like a spreadsheet formula gets a leading apostrophe.
- Debug runs with `-UseSampleData` also write the snapshot, so widgets show the sample data until the next normal run goes to the background.

Original → replacement:

| Original | Replacement |
|---|---|
| Live Tiles per account and goal | WidgetKit widgets, using an App Group to share the data store |
| App password | Face ID / passcode via `LocalAuthentication` |
| SkyDrive backup | CSV/JSON export via `ShareLink` or `.fileExporter`; iCloud if sync is turned on |
| Azure sync | SwiftData CloudKit sync (deferred, see Decisions) |
| Authorized users | CloudKit sharing (deferred, see Decisions) |
| Rate the app | `RequestReviewAction` |
| 44-language strings | String Catalog, English first |
| Settings | A Settings screen; on macOS, a `Settings` scene |

## Open items

- **Long register rows**: the details line now wraps to two lines instead of being cut off at one. Check it on a narrow iPhone.
- **visionOS** is listed in the target but hasn't been built. There's no visionOS simulator installed.
- **Mac signing**: the App Group needs a Mac provisioning profile. Sign in to Xcode (Settings → Accounts) so automatic signing can create it; until then the Mac build fails at signing (it compiles with signing off).
- **`xcuserdata` is committed to git**: `Stirling Money.xcodeproj/xcuserdata/shane.xcuserdatad/xcschemes/xcschememanagement.plist` is per-user Xcode state and could be untracked.
- **The register sorts transactions in memory.** That's fine for personal ledgers; switch to a `@Query` with a predicate if large accounts get slow.
