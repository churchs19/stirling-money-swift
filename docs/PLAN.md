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
| 7 | Apple Watch app (read-only) and complications | Done; checked on simulators and a real iPhone and Watch |
| 8 | Budget widgets (iPhone, iPad, Mac, Lock Screen, Watch) | Done; checked on simulators and a real iPhone, Watch and Mac |
| 9 | Test coverage: isolated unit tests, real UI tests, testable widget, lock and writer logic | Planned |

## Decisions

| Question | Decision |
|---|---|
| Platforms | iOS, iPadOS and macOS from one multiplatform target, plus a watchOS app (Phase 7). visionOS is also listed in the target but hasn't been built or tested. |
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
- **Widgets read a JSON snapshot**, not the SwiftData store: the widget target can't share the model files without per-file membership changes. The app rewrites it about a second after each save (SwiftData autosaves soon after every change), when it goes to the background, and when the Mac app quits. Background alone wasn't enough on the Mac, where switching apps doesn't count as backgrounding.
- Tapping a Balance widget set to one account opens that account's register (`widgetURL` → `onOpenURL`, see `DeepLink`); "All Accounts" just opens the app. Tapping a Goal widget opens the Goals tab (`stirlingmoney://goals`). On the Mac, links go to the open window rather than opening another (`handlesExternalEvents`). Confirmed on the simulator; the `stirlingmoney` scheme doesn't need registering in Info.plist for widget links.
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

### Phase 7: Apple Watch app (done)

A read-only watchOS companion: accounts with their balances, budgets and goals, plus complications.
Decisions (Nov 10, 2026): the iPhone sends the Watch a summary now, and the Watch moves to iCloud sync once
sync is turned on; read-only first; complications included; targets added with Xcode's own tools.

**How the data gets there.** The Watch can't read the iPhone's store or App Group, and iCloud sync is off
(the personal team can't use iCloud). So the iPhone sends the same kind of JSON summary the widgets read,
over WatchConnectivity:

- `WCSession.updateApplicationContext`: the system keeps only the latest one and delivers it when the
  Watch app next runs, which suits "current balances". It's sent by `WidgetSnapshotWriter` whenever it
  writes the widget snapshot (after each save, on going to the background), so there's one trigger for both.
- When the Watch app opens and the iPhone is reachable, it asks for a fresh summary with `sendMessage`;
  iOS can wake the iPhone app in the background to answer. When it isn't reachable, the Watch shows the
  last summary with "Updated 2 hours ago".
- The Watch app saves the summary to its own App Group container, so the Watch complications can read it
  (the same pattern as the iPhone widgets).
- Mac and iPad: WatchConnectivity is iPhone-only. The code is in `#if os(iOS)` and checks
  `WCSession.isSupported()`.

**The summary.** `WidgetSnapshot` gains:
- `budgets`: name, category name (or "All Spending"), amount, spent, period start/end, and over-budget,
  worked out on the iPhone by `Budget.summary`.
- `accent`: the chosen accent color, so the Watch matches the iPhone.

New fields are optional or have defaults, so existing snapshots still decode. The summary is a point in time:
once a budget's period has ended, the Watch shows "Open Stirling Money on iPhone to update" instead of last
period's spending.

**Shared code.** There are already two copies of `WidgetSnapshot`; a Watch app and Watch widgets would make
four. Instead, add a `Shared/` synchronized folder that belongs to all four targets: the app, the iPhone widgets,
the Watch app and the Watch widgets. It would hold `WidgetSnapshot`, the accent color decoding and
the account icon view. PaymentFont goes in it too (the font plus the glyph table), so payment logos work
everywhere. This replaces the current widget copies and the "keep in step" rule.

**Watch app screens** (SwiftUI, `NavigationStack`, vertical-page `TabView`):
1. **Accounts**: the total at the top, then each account's icon, name and balance (red when negative).
   Tapping an account shows its balance and posted balance. There's no register in the first version.
2. **Budgets**: one card per budget: name, a progress bar in the accent color (red when over), "$X left"
   or "$X over", and the period's dates.
3. **Goals**: progress ring in the accent color (green when reached), amount to go, days left.
- The footer of each page shows when the summary was taken. With no summary yet, the Watch says
  "Open Stirling Money on your iPhone."

**Complications** (a watchOS WidgetKit extension; Smart Stack and watch faces):
- Balance: one account or the total. Families: `accessoryCircular` (icon), `accessoryRectangular`
  (name, balance, posted), `accessoryInline`, `accessoryCorner`.
- Goal: progress ring (`accessoryCircular`, `accessoryRectangular`).
- Configured with the same App Intents as the iPhone widgets, which move to `Shared/`. The Watch app
  reloads complication timelines when a new summary arrives.

**Project changes** (with Xcode's tools, as for the widgets; each one is confirmed before it's made):
1. A watchOS app target embedded in the iPhone app ("Watch App for Existing iOS App"), bundle ID
   `net.s-church.stirlingmoney.watchkitapp`, watchOS 27.
2. A watchOS widget extension target for the complications.
3. The App Group `group.net.s-church.stirlingmoney` on both Watch targets. On the Watch it only joins
   the Watch app and its complications; the iPhone's container is separate.
4. The `Shared/` folder's membership in all four targets, then deleting the two `WidgetSnapshot` copies.

**Order of work**
1. [x] Project changes 1–4. The build stays green, and the iPhone widgets read `WidgetSnapshot` from `Shared/`.
   Targets: `StirlingMoney Watch App` (`net.s-church.stirlingmoney.watchkitapp`) and
   `StirlingMoneyWatchWidgetsExtension`. The Watch app's dependency and embed phase are filtered to iOS, since a Mac
   app can't contain watchOS content.
2. [x] Add budgets and accent to the summary; tests for the new fields and for decoding old snapshots.
   Changing the accent color in Settings rewrites the summary too.
3. [x] `WatchSync` on the iPhone: a `WCSession` delegate. It sends the application context after each
   snapshot write and answers the Watch's refresh request from the main context.
   It replies with the summary file on disk (no hop to the main actor from the session's queue), then refreshes the
   file, which sends again if anything changed. It also sends the file when the session activates or a Watch app is
   installed. Confirmed on the paired simulators: "Sent a summary of 3394 bytes to the Watch".
4. [x] `WatchStore` on the Watch: an `@Observable` that receives the context, saves it to the App Group,
   loads it at launch and reloads complications. Tests for decoding and the "ended period" state.
   It ignores a summary older than the one it has (a reply and a context can arrive in either order), and
   asks the iPhone for a fresh one whenever the app comes to the front. The iPhone only rewrites the summary
   when something changes, so the Watch also notes when it last heard from the iPhone (`asOf`) for the
   "Updated …" footer. WatchConnectivity calls its handlers on its own queue, so they must be `@Sendable`, not
   main-actor closures (a main-actor reply handler crashed the app). Confirmed on the paired simulators.
5. [x] Watch screens: Accounts, Budgets, Goals, with previews using sample data.
   PaymentFont (font, license and glyph table), `.localCurrency` and the summary's icon view moved to `Shared/`, so
   there's one copy of each for the app, both widget extensions and the Watch. A budget whose period has ended shows
   "Open Stirling Money on your iPhone to update" instead of last period's figures.
6. [x] Complications; check them in the Watch simulator's Smart Stack and on a watch face.
   Balance and Goal, each in circular, rectangular, inline and corner. The watch face editor lists the total and each
   account (or each goal) through `recommendations()`. The account and goal pickers (`WidgetIntents.swift`) moved to
   `Shared/`. Checked with Xcode previews on the Watch simulator, including a corner and a tinted face, and on a real
   watch face (step 7).
7. [x] Paired iPhone + Watch simulators: change a balance on the iPhone and check that it reaches the Watch.
   Repeat with the Watch app closed and with the iPhone app in the background. Then a real Watch.
   - [x] Simulators (Nov 11, 2026), switching the iPhone between `-UseSampleData` and its own empty store as the change:
     Watch app open (updated within seconds); Watch app closed (the system started it in the background, and it
     showed the new data); iPhone app not running (opening the Watch app woke the iPhone app in the background, which
     answered with its current data).
   - Found and fixed: the iPhone only rewrote the summary after a save or on going to the background, so a launch
     with different data (or a rolled-over budget period) didn't reach the Watch. It now refreshes the summary at
     launch too.
   - [x] A real iPhone and Apple Watch (Nov 14, 2026; iPhone on iOS 27.2, Watch on watchOS 27.2.1): a balance changed
     on the iPhone reaches the Watch app, and the Balance and Goal complications work on a real watch face.
   - Signing: at first the Watch refused the app because it wasn't registered with the team (its profiles listed only
     iPhones). Once Xcode could see the Watch (paired, unlocked, Developer Mode on), building the Watch app for it with
     `-allowProvisioningUpdates -allowProvisioningDeviceRegistration` registered it and remade both Watch profiles.
   - Found and fixed: the Watch app asked the iPhone for a summary only when it came to the front, and at launch that
     runs before its session has activated, so the request was skipped and never retried. It now asks again when the
     session activates and whenever the iPhone becomes reachable. Both apps log their session state at notice level,
     so it shows in the device console (`devicectl device process launch --console` with `OS_ACTIVITY_DT_MODE=enable`).
   - Found and fixed: the watch face editor offered only "All Accounts" and no goals, because watchOS caches the
     complications' `recommendations()` and they were first made before any summary arrived. The Watch app now calls
     `WidgetCenter.invalidateConfigurationRecommendations()` at launch and whenever a new summary adds, renames or
     removes an account or goal. Confirmed on the real Watch (Nov 14, 2026): each account and goal can be picked.
8. [x] README, CLAUDE.md (targets, `Shared/`, the WatchConnectivity flow), and this plan.

**Later: iCloud sync.** Once a paid team turns on CloudKit (see the `cloudkit-sync` branch), the Watch can
open the same SwiftData store with `cloudKitDatabase: .private(...)` and drop the summary. That needs the
model files and `Ledger` in `Shared/` too, which also makes it possible to add transactions on the Watch.
Until then:
- Read-only: with no sync, a transaction entered on the Watch would have to be sent to the iPhone and
  could be lost if the iPhone never received it.

**Risks and questions**
- **Stale data.** The Watch is only as current as the iPhone's last run; the "Updated …" footer makes that
  visible. Background app refresh on the iPhone isn't planned. It could resend the summary on a schedule.
- **Privacy.** The iPhone's "Require Face ID" lock doesn't apply on the Watch; balances show whenever the
  Watch is unlocked (wrist detection plus its passcode). If that's not acceptable, hide amounts until tapped.
- **Sample data.** Debug runs with `-UseSampleData` send the sample summary to the Watch too, like the widgets.
- **Signing.** The free personal team can install Watch apps, with the same 7-day expiry as the iPhone app.
  Each Watch target needs its own App Group profile, which automatic signing creates.

### Phase 8: Budget widgets (done)

Widgets that show budgets the way the Budgets screen's cards do (`BudgetRow`): the name and what it covers
(category or "All Spending"), a bar in the accent color (red when over), "$X of $Y", "$X left" or "$X over", and
the period with its dates ("Monthly · Nov 1 – 30").
Decisions (Nov 18, 2026): both a single-budget widget you configure and a list of every budget; on the iPhone and
iPad home screen, the Mac desktop, the iPhone Lock Screen and the Apple Watch; when a period has ended, show
"Open Stirling Money to update." instead of last period's figures (as the Watch app does).

**The data is already there.** The summary (`WidgetSnapshot.budgets`) has each budget in an active period, sorted
by name like the Budgets screen, with spent, limit and period dates. It lacks the period's name ("Monthly"), so:
- Add `periodTitle: String?` to `BudgetSummary` (worked out on the iPhone from `Budget.period.title`; optional, so
  older summaries still decode).

**Shared card.** A `BudgetSummaryCard` view in `Shared/` draws one budget from a `BudgetSummary` like `BudgetRow`,
with a compact layout for small spaces. The iPhone widgets, the Watch app's Budgets page and the complications use
it. (The app's own `BudgetRow` keeps working from the models; it also handles "Starts …" for budgets not yet started,
which the summary leaves out.)

**Widgets** (in the existing widget extension, so the iPhone, iPad and Mac all get them):
1. **Budget** (one budget, configured with a new `SelectBudgetIntent`/`BudgetEntity` in `Shared/WidgetIntents.swift`,
   like Goal; unconfigured shows the first budget):
   - Small: name, category, bar, "$X left" or "$X over", period dates.
   - Medium: the full card, as on the Budgets screen.
   - Lock Screen (iPhone): rectangular (name, bar, "$X left"), circular (ring of the amount spent, "$X left" below
     where it fits), inline ("Groceries: $120 left").
2. **All Budgets** (every budget, no setup; same order as the Budgets screen, as many as fit):
   - Medium: 2 cards; large: 3; extra large (iPad and Mac): 6 in two columns. "+3 more" when they don't all fit.
- Both open the app's Budgets tab: add `stirlingmoney://budgets` to `DeepLink`.
- Timeline: one entry, reloaded when the app writes new data (as now) and at the end of the earliest period shown, so
  an ended period switches to "Open Stirling Money to update."
- No budgets: "Add a budget in Stirling Money." A configured budget that was deleted (or whose period ended and the
  app has since left it out): "This budget isn't available. Edit the widget to choose another."

**Watch:** a **Budget** complication (circular, rectangular, inline, corner), chosen in the watch face editor through
`recommendations()` (one per budget), like Balance and Goal. `WatchStore.complicationChoicesChanged` includes budgets,
so the list is rebuilt when one is added, renamed or removed. A list of budgets doesn't fit any Watch family, so the
"Budgets" list widget is iPhone, iPad and Mac only.

**Project changes:** none expected. New files go in the existing synchronized folders (`StirlingMoneyWidgets/`,
`StirlingMoneyWatchWidgets/`, `Shared/`), and both widget bundles just list the new widgets.

**Order of work**
1. [x] `periodTitle` in the summary; tests for it and for decoding a summary without it.
   It's an optional with a default, so the synthesized decoder reads summaries without it (the iPhone and Watch may
   briefly run different versions). The sample summary has "Monthly" and "Weekly" for previews.
2. [x] `BudgetSummaryCard` in `Shared/` (full and compact), with previews; the Watch app's Budgets page uses it.
   Full matches `BudgetRow` ("$275.00 of $400.00", "Monthly · Nov 8 – Dec 7, 2026"); compact stacks the name over the
   category and drops "of $Y" and the year. `BudgetSummary.periodText(withYear:)` builds the period line. Callers add
   their own padding. Checked in previews on the iPhone and the Watch.
3. [x] `SelectBudgetIntent`/`BudgetEntity`; the Budget widget (small, medium, Lock Screen) and `stirlingmoney://budgets`.
   Small uses the compact card, medium the full one; Lock Screen rectangular (name, bar, "$X left"), circular (ring of
   spending, amount left in compact notation, negative when over) and inline. Unconfigured shows the first budget. The
   timeline reloads at the end of the shown budget's period. Checked in previews (Lock Screen ones only render in
   interactive mode; static snapshots come out blank).
4. [x] The Budgets list widget (medium, large, extra large); a test for how many fit and the "+N more" count.
   Two full cards don't fit a medium widget, so the card gained a `dense` style (the full card without the period
   line): medium shows 2 dense cards with no heading (and so no "+N more"); large a "Budgets" heading, "+N more" and 3
   full cards; extra large (iPad and Mac) 6 full cards in two columns. `WidgetSnapshot.budgetsToList` picks them. The
   timeline reloads when the earliest shown period ends. Checked in previews on the iPhone and the iPad.
5. [x] The Watch Budget complication and its recommendations; extend the recommendations test to budgets.
   Rectangular: name in the accent color, a bar (red when over), "$X left" or "$X over". Circular: a ring with the
   amount left in compact notation (negative when over). Corner: the amount left with a curved bar. Inline:
   "Food: $125.00 left". After the period ends it asks for the iPhone app instead. Unconfigured shows the first budget;
   the timeline reloads at the period's end. `complicationChoicesChanged` now includes budgets. Checked in previews.
6. [x] Check on the iPhone and iPad simulators, the Mac, the Watch simulator, then the real iPhone and Watch.
   - [x] Simulators and previews (Nov 18, 2026): the iPhone writes `periodTitle` into the summary; every widget size and
     the four complications checked in previews (iPhone, iPad, Watch); the Watch app's Budgets page shows the iPhone's
     budgets in the shared card. Adding widgets to the simulator's home screen can't be driven reliably from here (the
     edit menu ignores injected taps), and `simctl openurl` can't test the link because the scheme isn't registered
     (widget links don't need it; the Budgets link has a unit test).
   - [x] On the real iPhone, Watch and Mac (Nov 18, 2026): the Budget, All Budgets and Lock Screen widgets and the
     Budget complication work. The list widget was renamed "All Budgets" in the gallery to tell it apart from "Budget".
7. [x] README, CLAUDE.md and this plan.

**Risks and questions**
- **Ended periods.** Widgets can't work out a new period's spending; they ask for the app to be opened until it
  writes a new summary. Background refresh on the iPhone would fix this, as noted for the Watch.
- **All-spending budgets** count every account's transactions, so writing the summary reads all transactions when one
  exists (as now). Fine for personal ledgers.
- **Privacy on the Lock Screen.** Budget amounts show on a locked iPhone, as balances already do. Marking amounts
  `privacySensitive()` would hide them while locked; worth deciding for the Balance widget at the same time.
- **Widget gallery.** Two budget widgets plus Balance and Goal makes four; the names "Budget" and "All Budgets" with
  descriptions ("One budget's spending this period", "Every budget's spending this period") keep them apart.

### Phase 9: Test coverage (planned)

From a review of the tests on Nov 18, 2026. There are 85 iPhone unit tests and 8 Watch unit tests (Swift Testing, all
passing), and two UI tests in each UI test target, both Xcode's templates that check nothing.
Code coverage of the unit tests:
- **Models and calculations:** 80–100% (`Ledger` 96%, `TransactionDraft` 100%, `Budget` 98%, `Reports` 81%; the
  report gaps are only sort tie-breaks).
- **Untested logic:**
  - `AppLock`: 15%.
  - The widget pickers' queries (`WidgetIntents.swift`): 0%.
  - `ChartPalette`: 0%.
  - `BudgetSummaryCard`: 10%; only `periodText` is tested.
  - The widget and complication providers: no test target at all.

**Problems found**
- **Unit tests run inside the real app.** The test target's host is the app, so every run opens the simulator's real
  store, rewrites the widget summary and tries to send it to the Watch. Some coverage is borrowed from that launch, not
  earned by tests: `AccountsView` 50%, `WidgetSnapshotWriter` 90%.
- **Placeholder tests.** `Stirling_MoneyTests.example` and both UI test targets' `testExample` check nothing.
- **`AppLock` can't be tested.** It calls `LAContext` directly, and `isEnabled` reads `UserDefaults.standard` instead
  of the `defaults` passed to `init`.
- **The same choice rule is copied into each provider.** Each widget and complication provider has its own copy of
  "none chosen → the first; chosen one gone → a message", and none of them is tested.

**Order of work** (each step keeps every test passing and the iPhone, Watch and Mac builds green)

1. [x] **Isolate the unit tests from the app.**
   - When the app starts under tests (`XCTestConfigurationFilePath` in the environment), use an empty in-memory
     container and skip `WatchSync.start()` and `WidgetSnapshotWriter.startObserving`.
   - Delete `Stirling_MoneyTests.example`. Measure coverage again as the baseline for the steps below.
   - A code check, not a project change: making the tests hostless would mean changing the test target's `TEST_HOST`.
   - Done: `Stirling_MoneyApp.isHostingUnitTests` (tested by `TestHostTests`). When hosting tests the app also draws an
     empty window, so no screen counts as covered unless a test draws it. The placeholder test is gone.
   - **Baseline** (unit tests, Nov 18, 2026): 14.4% of the app (1073 of 7471 lines), down from a borrowed 20.3%.
     - Unchanged: `Ledger` 96%, `TransactionDraft` 100%, `Budget` 98%, `WidgetSnapshot+Models` 98%, `Reports` 81%.
     - Coverage that came only from the launch went to 0%: `WidgetSnapshotWriter`, `WatchSync`, `AccountsView`,
       `RootView`, `View+Accent`.
     - Two models dropped and were added to step 7: `AccountSort` (100% to 61%) and `AccountLayout` (100% to 20%).
2. [x] **One rule for which item a widget shows.**
   - Add `WidgetSnapshot` lookups to `Shared/` that return the item to show, or why there isn't one: no summary yet,
     none exist, or the chosen one is gone. "None chosen" means the first item, except for Balance, where it means
     the total.
   - The Balance, Goal and Budget widgets and the three complications use them.
   - Tests for each case, for accounts, goals and budgets.
   - Done: `Shared/WidgetChoice.swift` has `WidgetChoice<Item>` (item, noSummary, noneExist, missing) for goals and
     budgets, and `BalanceChoice` (total, account, noSummary, missing). All six providers use them, and
     `WidgetChoiceTests` covers each case (8 tests).
   - Fixed while here: the complications showed "Add a goal…" or "Add a budget…" when the chosen one was gone (and
     the Balance one "Open Stirling Money on your iPhone."). Like the iPhone widgets, they now tell the three cases apart:
     no summary yet, none exist, and "This goal was deleted / This budget is gone / This account was deleted. Edit the
     watch face to choose another." (`ComplicationEmptyState` and `ComplicationMessage` in the complications bundle.)
     Checked in Watch previews.
3. [ ] **Test the widget pickers.**
   - Give the entity queries a way to read a given summary instead of the App Group file (a `static var` source that
     tests set; `load()` stays the default).
   - Test `entities(for:)` with known, unknown and mixed IDs, and `suggestedEntities()` with no summary.
   - Test `WidgetSnapshot.load()` against a temporary file, and `total`.
4. [ ] **Test the summary writer's change check.**
   - Move "decode the existing file, ignore `updatedAt`, compare" into a function such as
     `WidgetSnapshot.needsWrite(_:existing:)`.
   - Test: no file, an unreadable file, the same figures at a later time (no write), and a changed balance, budget or
     accent (write).
5. [ ] **Make `AppLock` testable.**
   - Pass in the authentication (`(String) async -> Bool`) and "is a passcode set" (`() -> Bool`) checks, defaulting
     to `LAContext`.
   - Read `isEnabled` from the injected defaults.
   - Test:
     - It starts locked only when enabled.
     - Going to the background locks it only when enabled.
     - It prompts once per lock.
     - A cancel leaves it locked with no second prompt; Unlock asks again.
     - With no passcode it unlocks instead of shutting you out.
     - A second unlock while one is already in progress does nothing.
6. [ ] **Test parsing and display in other locales.**
   - Give `Decimal(userInput:)` and `.localCurrency` an optional locale (default `.current`).
   - Test en_US, de_DE ("1.250,75 €"), fr_FR (narrow no-break space grouping), de_CH ("1’250.75") and ja_JP (no
     decimals).
   - Check that text shown with `.localCurrency` parses back, and that CSV export still writes "." whatever the locale.
7. [ ] **Fill the smaller gaps.**
   - `ChartPalette.color(slot:)`: slots 0–7, then nil and 8 fall back to "Other".
   - `AccountSort` and `AccountLayout`: the parts only the app's launch used to cover (titles, icons, sorting edge
     cases).
   - `GoalDraft.hasInvalidTarget`.
   - `BudgetDraft(editing:)` for a budget with an end date and a custom period.
   - `DateInterval.formattedDays`, or replace it with `BudgetSummary.periodText` so there's one formatter.
   - The tie-break order in `Reports.spendingByCategory`.
   - **Account links:** move "which account a link opens" out of `RootView.open(_:)` into a function, and test a known
     ID, a deleted account and a bad ID.
8. [ ] **Prepare the app for UI tests.**
   - A `-UITesting` launch argument (Debug only) that:
     - Implies `-UseSampleData`.
     - Turns the app lock off.
     - Keeps settings in a fresh `UserDefaults` suite, so the accent, layout and sort start at their defaults.
     - Skips the widget summary and Watch.
   - `accessibilityIdentifier`s on the controls the tests drive: the add buttons, the account tiles and rows, the form
     fields, Save, the tabs and the Settings controls.
9. [ ] **Real iPhone UI tests** (replacing the template; on the iPhone simulator, one `XCUIApplication` per test with
   `-UITesting`):
   - Launch: the Accounts tab shows the sample total and three tiles.
   - Add an account with an opening balance; the total goes up by that amount.
   - Add a withdrawal to Checking; its balance and the total go down.
   - Transfer between two accounts; both balances change and the total doesn't.
   - Search the register by payee.
   - Mark a transaction posted; the posted balance changes.
   - Add a budget and a goal; their cards show on Budgets and Goals.
   - Reports: each report opens.
   - Settings: switch to the list layout and back, choose a custom accent.
   - Keep the launch performance test, which is fine as it is.
   - Optional later: run the same suite on an iPad simulator; on the Mac, check the sidebar and the Settings window.
10. [ ] **A Watch UI smoke test.**
    - The Watch app's own `-UseSampleData` loads `WidgetSnapshot.sample` instead of the saved summary.
    - Replace the template with: the Accounts page shows the total, then swipe to Budgets and Goals.
11. [ ] **README, CLAUDE.md** (how to run each test target and the `-UITesting` argument) **and this plan**, with the
    new coverage figures.

**Not planned:** unit tests of SwiftUI layout, charts or widget rendering. Previews and checks on the devices suit those
better.

**Risks and questions**
- **UI test speed and flakiness.** Each test launches the app: keep about ten, use identifiers rather than labels, and
  wait for elements instead of sleeping.
- **Detecting tests at launch** relies on an Xcode environment variable. If that ever changes, the hostless test target
  is the fallback, and it needs an approved project change.
- **Locale tests** depend on Foundation's formatting data. Assert that values round-trip, not exact strings, except
  where the separator is the point of the test.

## Open items

- **Long register rows**: the details line now wraps to two lines instead of being cut off at one. Check it on a narrow iPhone.
- **visionOS** is listed in the target but hasn't been built. There's no visionOS simulator installed.
- **The register sorts transactions in memory.** That's fine for personal ledgers; switch to a `@Query` with a predicate if large accounts get slow.
