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
| 9 | Test coverage: isolated unit tests, real UI tests, testable widget, lock and writer logic | Done |
| 10 | Recurring transactions, added on schedule; widgets and the Watch show them on the day | Done; background timing still to watch on the iPhone |
| 11 | iCloud sync and sharing books with other Apple IDs (CKSyncEngine) | Planned |

## Decisions

| Question | Decision |
|---|---|
| Platforms | iOS, iPadOS and macOS from one multiplatform target, plus a watchOS app (Phase 7). visionOS is also listed in the target but hasn't been built or tested. |
| CloudKit sync | **Planned in Phase 11** (Nov 20, 2026; a paid developer account is now available). Models are kept CloudKit-compatible (every property has a default or is optional, every relationship is optional, no unique constraints). |
| Sharing data with other people | **Planned in Phase 11:** books shared with other Apple IDs through CloudKit sharing, synced by our own `CKSyncEngine` layer because SwiftData's built-in sync has no shared database. |
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

### Phase 9: Test coverage (done)

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
3. [x] **Test the widget pickers.**
   - Give the entity queries a way to read a given summary instead of the App Group file (a `static var` source that
     tests set; `load()` stays the default).
   - Test `entities(for:)` with known, unknown and mixed IDs, and `suggestedEntities()` with no summary.
   - Test `WidgetSnapshot.load()` against a temporary file, and `total`.
   - Done: each query has a `summary` closure (default `WidgetSnapshot.load()`), set through the memberwise
     initializer in tests rather than a shared static, so tests can't interfere with each other. `load()` now calls
     `load(from:)`. `WidgetPickerTests` (6 tests) covers the three pickers, lookups with known, deleted, mixed and no
     IDs, loading a saved, missing or unreadable file, and `total` with a negative balance. The App Intents metadata
     still builds without warnings for the iPhone, Watch and Mac widgets.
4. [x] **Test the summary writer's change check.**
   - Move "decode the existing file, ignore `updatedAt`, compare" into a function such as
     `WidgetSnapshot.needsWrite(_:existing:)`.
   - Test: no file, an unreadable file, the same figures at a later time (no write), and a changed balance, budget or
     accent (write).
   - Done: `WidgetSnapshot.needsWrite(over:)` in `Shared/`, used by `WidgetSnapshotWriter`; `WidgetSnapshotWriteTests`
     (7 tests).
   - Bug found and fixed: with a custom accent color, every update counted as a change, because the color's `Float`s
     don't come back from JSON exactly. So the app rewrote the summary, reloaded every widget and sent the Watch the
     same figures on every save, at launch and on every trip to the background. It now compares both summaries as
     saved (the new one is encoded and decoded first).
5. [x] **Make `AppLock` testable.**
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
   - Done: `AppLock(defaults:canAuthenticate:authenticator:)`, defaulting to `AppLock.isAvailable` and
     `AppLock.askDeviceOwner` (`LAContext`). `isEnabled` now reads the injected store; with the old code, a lock turned
     on in a test or a second store would have been ignored. `AppLockTests` (9 tests) uses a stand-in for Face ID, and
     one test holds the prompt open to check that a second tap on Unlock doesn't open another.
6. [x] **Test parsing and display in other locales.**
   - Give `Decimal(userInput:)` and `.localCurrency` an optional locale (default `.current`).
   - Test en_US, de_DE ("1.250,75 €"), fr_FR (narrow no-break space grouping), de_CH ("1’250.75") and ja_JP (no
     decimals).
   - Check that text shown with `.localCurrency` parses back, and that CSV export still writes "." whatever the locale.
   - Done: `.localCurrency(in:)`, `Decimal(userInput:locale:)`, `Decimal(positiveUserInput:locale:)` and
     `editableText(in:)`, all defaulting to the current locale. `LocaleTests` covers en_US, en_GB, de_DE, fr_FR, de_CH,
     ja_JP, es_MX and ar_SA: shown amounts (including negative and over a million) and editable text parse back, each
     locale reads its own separators and symbol, a locale with no region falls back to dollars, and CSV amounts keep
     "." (they use `Decimal`'s description). No locale bugs found.
7. [x] **Fill the smaller gaps.**
   - `ChartPalette.color(slot:)`: slots 0–7, then nil and 8 fall back to "Other".
   - `AccountSort` and `AccountLayout`: the parts only the app's launch used to cover (titles, icons, sorting edge
     cases).
   - `GoalDraft.hasInvalidTarget`.
   - `BudgetDraft(editing:)` for a budget with an end date and a custom period.
   - `DateInterval.formattedDays`, or replace it with `BudgetSummary.periodText` so there's one formatter.
   - The tie-break order in `Reports.spendingByCategory`.
   - **Account links:** move "which account a link opens" out of `RootView.open(_:)` into a function, and test a known
     ID, a deleted account and a bad ID.
   - Done (16 tests, added to the files that already cover each area, plus `ChartPaletteTests`):
     - `DateInterval.formattedDays(withYear:)` moved to `Shared/DateInterval+Days.swift`. `BudgetSummary.periodText`
       uses it, so the Budgets screen, budget history, widgets and Watch share one formatter.
     - `DeepLink.account(withWidgetID:in:)` is now used by `RootView`.
     - `BudgetSummaryCard`'s helper extensions are `nonisolated`.
   - Coverage after step 7: 16.4% of the app (from 14.4%):
     - `ChartPalette`, `AccountLayout`, `DeepLink`, `WidgetChoice` and the money formatting and parsing: 100%.
     - `GoalDraft` 98%, `BudgetDraft` 95%, `AccountSort` 87%.
     - What's left in these files only runs with the system: `AppLock`'s `LAContext` calls (63%), the pickers' display
       names (`WidgetIntents`, 45%), and `WidgetSnapshotWriter`'s fetch-and-write (0%; its decision is
       `needsWrite`, tested in step 4).
8. [x] **Prepare the app for UI tests.**
   - A `-UITesting` launch argument (Debug only) that:
     - Implies `-UseSampleData`.
     - Turns the app lock off.
     - Keeps settings in a fresh `UserDefaults` suite, so the accent, layout and sort start at their defaults.
     - Skips the widget summary and Watch.
   - `accessibilityIdentifier`s on the controls the tests drive: the add buttons, the account tiles and rows, the form
     fields, Save, the tabs and the Settings controls.
   - Done: `LaunchMode` (`Stirling Money/Models/LaunchMode.swift`) holds `isHostingUnitTests` (moved from the app),
     `isUITesting` and `settings`. Under `-UITesting`, `settings` is a store of its own, emptied at launch. The app
     uses it for `@AppStorage` (`.defaultAppStorage`), for `AppLock`, and for `AccentChoice.store` in place of the
     App Group.
   - Checked on the simulator: with the layout saved as list, a `-UITesting` launch shows the sample data in tiles,
     and a normal launch still shows the list.
   - Identifiers:
     - Accounts: `addAccount`, `toggleLayout`, `settings`, `accountsTotal`, `account.<name>`.
     - New account: `accountName`, `initialBalance`.
     - Register: `addTransaction`, `availableBalance`, `postedBalance`, `transaction.<payee>`.
     - Transaction form: `transactionType`, `amount`, `payee`, `otherAccount`, `transactionPosted`.
     - Budgets and goals: `addBudget`, `budget.<name>`, `budgetName`, `budgetAmount`; `addGoal`, `goal.<name>`,
       `goalName`, `goalTarget`, `goalAccount`.
     - Reports: `report.<case>`.
     - Settings: `sortAccounts`, `accentChoice`, `customAccent`.
     - Every form's Save button: `save`. `CurrencyField` takes an `identifier` for its text field.
9. [x] **Real iPhone UI tests** (replacing the template; on the iPhone simulator, one `XCUIApplication` per test with
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
   - Done: 11 tests plus launch performance in `Stirling_MoneyUITests`, about 4 minutes on the iPhone simulator.
     They passed twice in a row.
   - Each test launches with `-UITesting -AppleLanguages (en) -AppleLocale en_US`, so amounts read the same whatever
     the simulator's language. The performance test uses the same arguments.
   - SwiftUI folds an amount into the label of its row or tile ("Total, $19,660.73"), so the tests wait for that
     label to contain the amount (`expectLabel(of:toContain:)`) rather than looking for a text element.
   - The register's search field is hidden under the title until the list is pulled down.
   - A row's posted checkmark is a button that carries the row's identifier, and it reads "Posted" or "Not posted".
   - The register's balances are checked through `availableBalance` and `postedBalance`, the accounts screen's
     through `accountsTotal` and each tile.
10. [x] **A Watch UI smoke test.**
    - The Watch app's own `-UseSampleData` loads `WidgetSnapshot.sample` instead of the saved summary.
    - Replace the template with: the Accounts page shows the total, then swipe to Budgets and Goals.
    - Done: `-UseSampleData` in the Watch app (Debug only) shows `WidgetSnapshot.sample` and skips the WatchConnectivity
      session and refresh requests, so the test needs no paired iPhone.
    - `StirlingMoney_Watch_AppUITests`: the three pages with the sample's amounts, tapping an account to see its posted
      balance, and launch performance, about 1 minute on the Watch simulator.
    - A page's list scrolls to its end before the next page comes in, so the test swipes until the next page's title
      can be tapped.
11. [x] **README, CLAUDE.md** (how to run each test target and the `-UITesting` argument) **and this plan**, with the
    new coverage figures.
    - Done (Nov 18, 2026). Where the tests stand:
      - **iPhone unit tests:** 137 (from 85).
      - **iPhone UI tests:** 11 plus launch time (from a template).
      - **Watch unit tests:** 8.
      - **Watch UI tests:** 2 plus launch time (from a template).
    - Unit-test coverage of the app is 16.4% of lines, against an honest 14.4% baseline. Models and logic are at 80–100%;
      screens are left to the UI tests.
    - Bugs found on the way:
      - A custom accent color made every update rewrite the widget summary and resend it to the Watch (step 4).
      - `AppLock.isEnabled` ignored the store it was given (step 5).
      - The Watch complications showed "Add a goal…" for a deleted goal (step 2).

**Not planned:** unit tests of SwiftUI layout, charts or widget rendering. Previews and checks on the devices suit those
better.

**Risks and questions**
- **UI test speed and flakiness.** Each test launches the app: keep about ten, use identifiers rather than labels, and
  wait for elements instead of sleeping.
- **Detecting tests at launch** relies on an Xcode environment variable. If that ever changes, the hostless test target
  is the fallback, and it needs an approved project change.
- **Locale tests** depend on Foundation's formatting data. Assert that values round-trip, not exact strings, except
  where the separator is the point of the test.

### Phase 10: Recurring transactions (done, except the background-timing check)

Recurring transactions (rent, pay, subscriptions, regular transfers) are created automatically on their schedule and
change balances without opening the app.

**Decisions (Nov 19, 2026)**
- **While the app is closed:** iOS can't run an app at an exact time. So the app adds due transactions whenever iOS
  wakes it in the background, and always at launch. Meanwhile the widgets and the Watch count anything that has come
  due, so the balances you see change on the day itself.
- **Schedules:** every N weeks on a weekday, every N months on a day of the month, twice a month, and yearly.
- **How they're entered:** as ordinary unposted transactions that you can edit, delete or mark posted.
- **Where they're managed:** an "Upcoming" section in each account's register, and an all-accounts Recurring screen.

**Choices made here** (change any of them before starting):
- **Ends:** never (the default), on a date, or after a number of times.
- **Missed occurrences:** every occurrence that came due while the app didn't run is added, each on its own date.
  A rent payment missed during a two-month gap is added twice. The catch-up is capped at 400 per rule.
- **Types:** withdrawals, deposits, checks (each gets the account's next check number when it's added) and transfers
  (added as a linked pair through `Ledger`). The rule also sets the payee, category and note.
- **Editing a rule** changes future occurrences only. Transactions already added are ordinary transactions.
- **Deleting a rule** keeps the transactions it added. Deleting an account deletes its rules. A transfer rule whose
  other account is deleted stops, and is shown as needing attention.
- **Actions on an upcoming occurrence:** "Skip Next" moves the rule to the following date. "Add Now" adds the next
  occurrence today.

**The model** (CloudKit-compatible like the rest: defaults or optionals, optional relationships, no unique constraints):
- `RecurringTransaction` (`@Model`) holds what to add:
  - `kindRawValue`, `amount` (positive; the kind decides the sign, as in `Ledger`), `payee`, `note`, `category`.
  - `account`, and `otherAccount` for transfers.
  - The schedule: `frequencyRawValue` (weekly, monthly, twiceMonthly, yearly), `interval` (every N), `startDate`, and
    for twice a month the second day of the month. A day past the month's end means its last day, as budgets do.
  - The end: `endDate` or `remainingCount` (both optional).
  - `nextDate`: the next occurrence, which only moves forward.
- **Relationships:**
  - `Account.recurringTransactions` (cascade, inverse `account`).
  - `otherAccount` (nullify), with an inverse on `Account` so SwiftData can handle deleting the account.
  - `Category` (nullify).
  - `AccountTransaction.recurrence` (optional, nullify), so a transaction knows which rule added it. This shows a
    repeat icon in the register and offers "Edit Recurring…".
- `RecurrenceSchedule` (`nonisolated`, pure date math like `BudgetPeriod`) gives the occurrence after a date and the
  occurrences in a range. It's tested with a fixed UTC calendar.

**Adding due transactions** (`RecurringScheduler.addDue(in:now:calendar:)` in `Managers/`):
- **Which:** for each rule whose `nextDate` is on or before today (local days, not times), it adds the occurrence
  through `Ledger`, with that date, unposted, and linked to the rule. Then it advances `nextDate` and the end count,
  and repeats until `nextDate` is in the future or the rule has ended.
- **No duplicates:** advancing `nextDate` in the same save as the transaction it adds means an occurrence can't be
  added twice by the same store. (Duplicates across devices only matter once iCloud sync is on; see risks.)
- **Runs:** at launch, when the app becomes active, on the Mac every hour while it's open (the Mac can't be woken),
  and in the background on iPhone and iPad.
- **Background:** a SwiftUI `.backgroundTask(.appRefresh("net.s-church.stirlingmoney.recurring"))`. After each run,
  the app asks for the next wake-up at the earliest `nextDate` (`BGAppRefreshTaskRequest.earliestBeginDate`). iOS
  decides when that actually happens.
- **After adding:** saving triggers `WidgetSnapshotWriter` as usual, so the widgets and Watch get the real
  transactions.
- **Not under tests:** `LaunchMode.isHostingUnitTests` skips all of this. UI tests use the sample data's rules
  directly.

**Widgets and the Watch between runs** (so the balances they show change on the day):
- The summary gains `upcoming`: each rule's occurrences in the next 45 days (date, account ID, signed amount,
  other account ID for transfers, category name, kind). Older summaries decode with none.
- `WidgetSnapshot.projected(on:)` in `Shared/` returns the summary as it would be on a given day. It adds the
  occurrences due by then to:
  - account balances (not posted balances, since they arrive unposted) and the total;
  - goals on those accounts;
  - budgets whose category matches (or all-spending budgets, for withdrawals and checks) when the date falls in the
    budget's current period.
  It's pure and tested.
- The Balance, Goal, Budget and All Budgets widgets, the complications and the Watch app's pages use `projected(on:)`.
  Widget timelines add an entry at the start of each occurrence day in the next 45 days, so they switch at midnight
  without the app.
- Once the app runs, the real transactions replace the projection; the summary no longer lists them as upcoming.

**Screens**
- **Register:**
  - An "Upcoming" section above the transactions, listing the account's rules: payee, amount, schedule ("Monthly
    on the 1st"), next date, and a mark if one needs attention.
  - Tap to edit. A swipe and context menu give Skip Next, Add Now and Delete.
  - The + button becomes a menu: Add Transaction / Add Recurring Transaction.
- **Making a transaction recurring:** "Make Recurring…" in a transaction's swipe actions and context menu opens the
  recurring form filled from it.
- **`RecurringFormView`** (with a `RecurringDraft`, like the other forms):
  - The transaction's fields, as in `TransactionFormView`.
  - A Schedule section: frequency, "every N", start date, the second day for twice a month, and the end (never / on a
    date / after N times).
  - A preview line: "Next: Fri, Nov 21; then Dec 5, Dec 19".
- **Recurring screen:** every rule across accounts, grouped by account or sorted by next date (a toggle), with the
  same actions. It opens from the Accounts ⋯ menu on every platform. (The Mac app has no menu-bar commands yet; a
  "Recurring Transactions" item there could come later.)
- **Sample data:** the preview data gets a few rules: monthly rent, biweekly pay, a monthly transfer to Savings and a
  yearly subscription. Screens and UI tests then have something to show.

**Project changes** (to be confirmed before each is made, using Xcode's tools):
1. The app target's **Background Modes** capability with **Background fetch** (iOS only).
2. `BGTaskSchedulerPermittedIdentifiers` in the app's Info.plist, listing `net.s-church.stirlingmoney.recurring`.
- Done (Nov 19, 2026, approved). Both were made with Xcode's `AddInfoPlist`, which created `Stirling-Money-Info.plist`
  at the top of the repo and set the app target's `INFOPLIST_FILE` for Debug and Release. Its keys are merged with the
  generated ones (`GENERATE_INFOPLIST_FILE` stays on).
- Background fetch needs no entitlement. The built app has both keys, and the Mac build is unaffected.
- The new model needs no project change; it's added to `AppSchema`. SwiftData migrates by adding the new entity and
  optional relationships, which also stays CloudKit-compatible.

**Order of work**
1. [x] `RecurrenceSchedule` (weekly with interval, monthly with clamping, twice a month, yearly with Feb 29) and its
   tests.
   - Done: `Models/RecurrenceSchedule.swift` has `RecurrenceFrequency` and `RecurrenceSchedule`:
     `next(onOrAfter:)`, `next(after:)`, `occurrences(from:through:limit:)`, and `summary()` ("Every 2 weeks on Friday").
   - Occurrences are counted from the start date, so a clamped Feb 28 doesn't drag later months.
   - Twice a month uses the start's day plus `secondDay`, leaving out a day before the start. A day past the month's
     end means its last day.
   - `RecurrenceScheduleTests`: 15 tests (18 runs with the per-frequency arguments).
2. [x] `RecurringTransaction` and the relationships, in `AppSchema`. Tests for the delete rules (an account, the other
   account, a category, a rule).
   - Done: `Models/RecurringTransaction.swift`. The amount is stored positive and dates as days. It has `schedule`,
     `hasEnded(calendar:)`, `problem` (the account, or a transfer's other account, was deleted) and `displayPayee`.
   - Inverses, each declared on one side:
     - `Account.recurringTransactions` (cascade).
     - `Account.recurringTransfersIn` (nullify, for `otherAccount`).
     - `Category.recurringTransactions` (nullify).
     - `RecurringTransaction.transactions` (nullify, inverse `AccountTransaction.recurrence`).
   - `RecurringTransactionTests`: 10 tests. In test files, write `Stirling_Money.Category`: Swift Testing has a
     `Category` too.
   - Upgrading an existing store: the simulator's real store opened and gained the `ZRECURRINGTRANSACTION` table
     without trouble. The store is in the App Group's container, not the app's. The real devices are checked in
     step 9.
3. [x] `RecurringScheduler.addDue`. Tests for:
   - one due occurrence, a catch-up over several months, and nothing due;
   - the end date and end count;
   - transfers as linked pairs, check numbers, category and note;
   - Skip Next and Add Now;
   - running twice adds nothing new.
   - Done: `Managers/RecurringScheduler.swift` has `addDue(in:now:calendar:)`, `addNow`, `skipNext` and
     `nextDueDate` (for scheduling the background run).
   - Transfers link both halves to the rule. Checks take `account.nextCheckNumber` one by one. A rule with a `problem`
     is left where it is.
   - Skipping counts toward an "after N times" end.
   - `RecurringSchedulerTests`: 16 tests, which also cover a deposit twice a month, the catch-up cap of 400 per run
     carrying on next time, and an occurrence due late at night.
4. [x] Running it at launch, on becoming active, on the Mac's timer and in the background, after the project changes
   (with approval). Check a background run with Xcode's "Simulate Background Fetch" on the simulator and on the
   device.
   - Done: `Managers/RecurringRunner.swift`.
     - **When it runs:** `start` runs it at launch (after `WidgetSnapshotWriter` starts), when the app becomes active,
       and at midnight (`.NSCalendarDayChanged`). On the Mac it also runs every hour and when the Mac wakes.
     - **Background:** after each run, and when the app goes to the background, it asks for a background run at the
       earliest due date with the async `BGTaskScheduler.submitTaskRequest` (`submit` is deprecated in iOS 27). The
       app's scene handles `.backgroundTask(.appRefresh(...))` with `runInBackground()`, which also writes the widget
       summary straight away.
     - **Not under tests:** nothing runs under `LaunchMode.isTesting`, unit or UI.
   - Tests: `RecurringRunnerTests` checks the wake-up date and that the identifier is in the built Info.plist.
   - Not yet checked at run time: a launch actually adding a due rule (needs the sample-data rules from step 5), and a
     background run. The simulator doesn't run BGTasks, so on the device use the debugger:
     `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"net.s-church.stirlingmoney.recurring"]`
     (step 9).
5. [x] `RecurringDraft` and `RecurringFormView`, the register's Upcoming section, "Make Recurring…", and the
   Recurring screen. Sample-data rules. Form tests like the other drafts'.
   - **Draft** (`Models/RecurringDraft.swift`):
     - Validation: amount, payee or another account, every 1–99, two different days, an end after the start, a count
       above zero.
     - A preview of the next three dates.
     - `init(from:)` for "Make Recurring…": a month after the transaction; either half of a transfer moves money from
       the source.
     - Saving: editing the schedule recomputes `nextDate` from today, so past occurrences aren't added again.
     - `RecurringDraftTests`: 14 tests.
   - **Screens:**
     - `RecurringFormView`: type, amount, account (a picker, so the Recurring screen can add too), payee or "To
       Account", category; then the schedule with its preview, the end, a note, and Delete when editing. Saving runs
       `RecurringRunner.run()`, so a rule starting today is added at once.
     - `RecurringRow` and `recurringRowActions`: Edit, Skip Next, Add Now and Delete, as swipes and a context menu.
     - The register's Upcoming section (the account's rules, plus transfers into it, read as "Transfer from …"),
       hidden while searching.
     - "Make Recurring…" or "Edit Recurring…" on each transaction, and a repeat icon on transactions a rule added.
     - `RecurringListView`, grouped by account or by next date, from "Recurring" in the Accounts ⋯ menu.
   - **Changed from the plan:** "Add Recurring Transaction" is in the register's ⋯ menu instead of turning + into a
     menu, so adding an ordinary transaction stays one tap (and the existing UI tests didn't change).
   - **Sample data:** rent (check, monthly), pay (twice a month), $400 to Savings monthly, and a yearly
     subscription on the Credit Card. All start in the future, so the sample balances don't change by date.
   - **Checked on the simulator:**
     - Upcoming, the form and its preview, and the Recurring screen.
     - Saving a $15 "Gym" rule starting today added it straight away (unposted, with the repeat icon; Checking went
       from $10,229.11 to $10,214.11), and its next date moved to a month later. This is also step 4's pending check.
   - The 11 iPhone UI tests still pass, and the Mac builds.
6. [x] `upcoming` in the summary and `WidgetSnapshot.projected(on:)`, with tests for:
   - balances and the total;
   - transfers (the total doesn't change);
   - goals;
   - budgets, both by category and all-spending, inside and outside the current period;
   - decoding old summaries.
   - Done: `Shared/WidgetSnapshot+Projection.swift` has `UpcomingOccurrence`, `projected(on:)`, `upcomingDays(after:)`,
     `BudgetSummary.counts(_:)` (the same rule as `Budget.spent`) and `GoalSummary.progress(current:target:initial:)`,
     which `Goal.progress` now uses too.
   - Goal summaries gained an optional `accountID` and `initialBalance`, which the projection needs. Older summaries
     decode without them, and their goals just don't move.
   - The app builds `upcoming` from `RecurringTransaction.upcomingDates(through:)`, which respects the end date and
     count and skips rules that need attention. `WidgetSnapshotWriter` passes the rules in.
   - `WidgetProjectionTests`: 12 tests. One builds the summary before `addDue`, projects it, then compares it with the
     summary after `addDue`: balances, posted balances, goal amounts and progress, and budget spending all match.
7. [x] The widgets, complications and Watch pages use the projection; widget timelines get an entry per occurrence
   day. Check in previews and on the simulator.
   - Done: `WidgetSnapshot.timelineDates(now:adding:)` gives now, each due day and extra moments (a budget period's
     end, midnight for days left). Each provider (Balance, Goal, Budget, All Budgets and the three complications) makes
     one entry per date from `projected(on:)` and reloads `.atEnd`. The Watch app's pages show the projection,
     redrawn hourly.
   - The Watch app's pages show `WatchStore.current`: the summary projected to `today`, which `showToday()` moves on
     whenever the app comes to the front (every wrist raise). A first attempt wrapped the pages in an hourly
     `TimelineView`, which kept the app from going idle: every UI-test query took about 30 seconds and the Watch UI test
     ran for 10 minutes or more. Neither `.periodic(from: .now, …)` nor a fixed start fixed that, so the TimelineView
     is gone.
   - 206 iPhone unit tests (one new for `timelineDates`), 9 Watch unit tests (one new for `current`), both Watch UI
     tests and the Mac build pass.
8. [x] UI tests: add a recurring transaction and see it in Upcoming; Skip Next; the Recurring screen.
   - Done: three tests in `Stirling_MoneyUITests`. Adding one checks the Upcoming row; under `-UITesting` the runner is
     off, so it's listed and the balance doesn't change. Skip Next checks the sample rent's next date before and after,
     worked out from today. The Recurring screen checks the rules from every account.
   - Found: items in a toolbar's ⋯ menu lose their accessibility identifiers, so tests find them by label
     (`menuItem(_:)`). The Settings test had only passed because its gear icon's accessibility label happened to be
     "settings". The unused identifiers on those menu items are removed.
9. [ ] Check on the simulators, the Mac, and the real iPhone and Watch. The background run needs a few days on the
   iPhone to see iOS's timing.
   - [x] Simulators: done along the way (steps 5, 7 and 8).
   - [x] Real iPhone and Watch (Nov 19, 2026): installed. The iPhone's existing store upgraded with the user's data (the
     app opened and kept running). `runInBackground` logs "Background run for recurring transactions" at notice level,
     so a collected device log can show whether iOS woke the app.
   - Note: once a store has upgraded, a build without `RecurringTransaction` (such as `main` before this phase is
     merged) can't open it. Merge before installing an older build on that device.
   - [ ] Over a day or two: a rule starting tomorrow shows in the widgets and on the Watch from midnight, and is added
     before the app is opened if iOS ran it in the background (check with `sudo log collect --device-udid … --last 2d`).
   - [x] The Mac with its real data (Nov 19, 2026): the store upgraded and the app opened and kept running.
10. [x] README, CLAUDE.md and this plan.
    - README: the feature, background refresh (with the debugger command to trigger it) and the layout. CLAUDE.md: the
      new files, relationships, how recurring transactions are added and projected, and two lessons for tests (overflow
      menu items lose identifiers; a screen-wide `TimelineView` keeps an app from going idle).

**Risks and questions**
- **Background timing:** iOS decides when, and how often, it wakes the app (less often for apps used rarely, and not
  in Low Power Mode). The widget projection covers the gap, and the app always catches up when opened.
- **The Mac** has no background wake-ups: the app adds due transactions when it's open, every hour while it stays
  open, and at launch. Its widgets use the projection.
- **iCloud sync later:** two devices could each add the same occurrence. When sync is turned on, add a de-duplication
  step that keeps one transaction per rule and date.
- **Budget projections** follow the same rules as `Budget.summary` (category spending less refunds; all spending
  leaves out transfers). One shared function keeps the two from drifting apart.
- **Time zones:** occurrences are local calendar days. A transaction's date is the start of that day, like ones
  entered by hand.

### Phase 11: iCloud sync and shared books (planned)

Sync everything through iCloud, and let an owner share a **book** of accounts with other people by their Apple ID, the
way the old app's "authorized users" worked. Nothing is built yet: this is the plan and the options considered.

**Decisions (Nov 20, 2026)**
- **Books:** data is organized into books, for example Personal, Household or Business. Each book can be shared or not,
  and the app has a book switcher.
- **Permissions:** the owner chooses per person, Can Edit or View Only, in the standard iCloud sharing sheet. View-only
  people see everything, and the app hides adding, editing and deleting for them. (CloudKit enforces it on the server
  too.)
- **Participants keep their own data:** their own books and the books shared with them sit side by side. The app, the
  widgets and the Watch show one book at a time.
- **Approach:** keep SwiftData as the local store and add our own sync layer with CloudKit's `CKSyncEngine`.

#### Options considered

SwiftData's built-in CloudKit sync (`ModelConfiguration(cloudKitDatabase:)`) offers only `.automatic`, `.private(_:)`
and `.none` in the iOS 27 SDK. It has no shared database, so it can sync one person's devices but can't share with
anyone else.

| | A. SwiftData + `CKSyncEngine` (chosen) | B. Core Data `NSPersistentCloudKitContainer` | C. SwiftData's private sync only |
|---|---|---|---|
| Sharing with other Apple IDs | Yes: zone-wide `CKShare` per book, one engine per database | Yes: built in (`share(_:to:)`, `acceptShareInvitations`) | No |
| Changes to existing code | Models gain a book and a sync ID; views filter by book. `@Query`, forms, `Ledger`, the tests and the widget summary stay | Every model becomes an `NSManagedObject`; `@Query` becomes `@FetchRequest`; drafts, `Ledger`, the tests and the widget builder are rewritten | Almost none (the `cloudkit-sync` branch is nearly done) |
| Sync code to own | Record mapping, applying fetched changes, conflicts, deletes: about 1,500–2,500 lines and tests | Little: Apple's mirroring does it | None |
| Control | Full: deterministic record names stop duplicate recurring transactions; our own conflict rules | Little: Apple's merge, no hook for duplicates | Little |
| Risks | Sync bugs are ours to find; more testing with two Apple IDs | A big rewrite; cross-share relationships aren't allowed; less is visible when it misbehaves | Has to be replaced to add sharing |

Why A: it keeps everything built in Phases 1–10. Sharing by book matches CloudKit's zone-wide shares exactly, one zone
per book. And the duplicate-occurrence problem from Phase 10 goes away, because record names are derived from the rule
and the date. B gets sharing for less sync code but rewrites the app around Core Data. C was the old plan; the
`cloudkit-sync` branch (SwiftData's private sync, `CategoryMerger`, `SyncMonitor` and Settings status) is superseded.
Its category merging, status UI and notes will be reused, and the branch deleted once Phase 11 lands.

#### Design

**Books in the model**
- A new `Book` `@Model`: `name`, `createdAt`, `syncID`, and cached sharing state: `isShared`, `isOwnedByMe`, `canEdit`,
  `ownerName`.
- `Account`, `Category`, `Budget`, `Goal`, `RecurringTransaction` and `AccountTransaction` each gain `book: Book?`. A
  transaction's book is always its account's, but storing it keeps the record-to-zone mapping simple.
- Transfers, goals and budgets only ever relate records in the same book. A book is a closed world, so it fits one
  CloudKit zone, and CloudKit references can't cross zones anyway.
- Every model gains `syncID: String = UUID().uuidString`, marked `@Attribute(.preserveValueOnDeletion)`, so a delete's
  history tombstone says which record to delete in CloudKit.
- **Upgrading:** the first launch of the new version puts all existing data in a new book, "My Book" (renamable). The
  new fields are optional or have defaults, so SwiftData's automatic migration covers it.
- **Switching:** the current book's `syncID` is stored in `LaunchMode.settings`. Every `@Query` and fetch filters by
  book: a shared `bookPredicate` and a `\.currentBook` environment value. Reports, totals, categories and budgets are
  then naturally per book.

**CloudKit layout**
- One CloudKit container: `iCloud.net.s-church.stirlingmoney`.
- **Owner:** each book is a custom zone (`Book-<syncID>`) in the owner's private database. Sharing a book is a
  zone-wide `CKShare` on that zone.
- **Participant:** after accepting, the book's zone appears in their shared database.
- **Records:** one record type per model. The record name is the model's `syncID`, and relationships are
  `CKRecord.Reference`s within the zone. Money (`Decimal`) is stored as a string to keep it exact, and dates as dates.
- **Deterministic names for generated records:** a recurring occurrence is named `"<rule syncID>:<yyyy-MM-dd>"`, and a
  transfer's halves `"<pair syncID>:out"` and `":in"`. Two devices adding the same occurrence then write the same
  record, so CloudKit keeps one: no duplicates, no clean-up pass.
- Each model stores its record's system fields (`ckSystemFields: Data?`), so saves send the change tag and conflicts are
  detected.

**The sync layer** (`Managers/Sync/`)
- `SyncCoordinator` owns two `CKSyncEngine`s, one for the private database and one for the shared database. Their saved
  state goes in the App Group folder.
- **Local changes out:** after each save, read SwiftData history since the last token, ignoring changes authored
  `"sync"`. Turn inserts and updates into pending record saves in the right zone, and deletes (tombstones) into pending
  record deletes. Prune history once it's sent.
- **Remote changes in:** for fetched records, insert or update models by `syncID` in a model context whose author is
  `"sync"`. Deleted record IDs delete the matching models. A deleted zone (a share stopped or left) deletes that book
  locally.
- **Conflicts** (`serverRecordChanged`):
  - Fields changed on only one side merge.
  - When both sides changed the same field, the later change wins, with these exceptions:
    - `isPosted` prefers true.
    - A rule's `nextDate` takes the later date, so occurrences aren't added twice.
    - Deletes win over edits.
  - Balances are always computed from transactions, so they need no merging.
- **Category names:** when a fetch brings in a category with the same name as one in the same book, `CategoryMerger`
  (from the `cloudkit-sync` branch) merges them into the oldest.
- **Status in Settings:** last synced, errors, the iCloud account state and "Sync Now".

**Sharing**
- **Owner:** "Share Book…" in the book switcher.
  - On iOS and iPadOS this is `UICloudSharingController` (or `ShareLink` with `CKShareTransferRepresentation`); on the Mac,
    `NSSharingService`.
  - Each person can be set to Can Edit or View Only in the system sheet.
  - "Manage Sharing…" changes people and permissions, or stops sharing.
- **Participant:**
  - Tapping the invitation link opens the app: `CKSharingSupported` in the Info.plist, and a scene delegate handling
    `userDidAcceptCloudKitShareWith`.
  - The app accepts the share; the shared engine fetches the zone; the book appears in the switcher with the owner's
    name.
  - "Leave Book" removes it.
- **View-only:** `canEdit` comes from the share's `currentUserParticipant.permission`. Forms, swipe actions, + buttons
  and recurring actions are hidden or disabled.
- **Recurring transactions in shared books:** any editor's device may add a due occurrence; the deterministic names
  make that safe. View-only participants never add them.
- **Widgets and the Watch:** the summary is written for the current book (with its name). The Watch shows that book.
  Choosing a book per widget can come later.

**Accounts and privacy**
- **Signed out of iCloud, or sync turned off:** the app works locally, and changes go up once sync is on.
- **Signed into a different Apple ID:** shared books from the old account are removed, and the user's own books stay
  local until they choose to upload or remove them. To be decided while building.
- **App lock:** still per device. Shared data is protected by each participant's own device.

#### Project changes (each confirmed before it's made, with Xcode's tools)
1. **iCloud** capability with **CloudKit** and the container `iCloud.net.s-church.stirlingmoney`, on the app target.
   Widgets and the Watch don't need it; they still read the summary.
2. **Push Notifications** (`aps-environment`), so CloudKit can tell the app about changes.
3. **Background Modes:** add Remote notifications to the existing Background fetch.
4. `CKSharingSupported` = YES in `Stirling-Money-Info.plist`.
5. **CloudKit Console:** create the container, deploy the schema to production before any TestFlight or App Store
   build, and only add to it afterwards (never rename or remove fields).

#### Order of work
1. [ ] Books: the `Book` model, `book` and `syncID` on every model, "My Book" for existing data, the switcher, and
   per-book queries everywhere (the reports and the widget summary too). Tests for upgrading an existing store and for
   per-book totals. No CloudKit yet: usable on its own.
2. [ ] Record mapping: each model to and from a `CKRecord`, with deterministic names, `Decimal` as a string and
   references. Round-trip tests with no network.
3. [ ] The project changes above (with approval), then the private engine: upload, fetch, apply, conflicts and deletes
   for the user's own books on their devices. A fake engine delegate in tests; then two devices on one Apple ID.
4. [ ] Sharing: share, accept, permissions, leave, stop sharing, and the shared engine. Two Apple IDs on two devices (or
   a device and a simulator).
5. [ ] View-only mode across the screens, and UI tests with a view-only book in the sample data.
6. [ ] Recurring transactions, widgets and the Watch with books and sharing: deterministic occurrence names, and the
   summary per current book.
7. [ ] Settings: sync status, Sync Now, and the iCloud account states. Category merging after fetches.
8. [ ] The CloudKit schema deployed to production; README, CLAUDE.md and this plan. Delete the `cloudkit-sync` branch.

**Risks and questions**
- **Size:** this is the largest phase so far: a sync engine is easy to get subtly wrong. Each step stays shippable (books
  work without sync, private sync without sharing), and the tests cover record mapping and conflict rules apart from
  CloudKit.
- **Testing sharing needs two Apple IDs.** A second test account on a second device (or a simulator signed in to it) is
  needed from step 4.
- **Limits:**
  - 100 participants per share.
  - A share per book uses one zone; zone counts aren't a practical concern at this scale.
  - Very large books take a while on the first download. `CKSyncEngine` pages it.
- **Schema changes become permanent** once deployed to production. Plan the record types carefully in step 2.
- **The Watch and widgets** see only the current book. Showing other books would need a per-widget book picker, which
  is left for later.
- **Privacy:** everyone with access to a book can see all its accounts. Books are the unit of sharing on purpose; to
  share less, make a separate book.

## Open items

- **Long register rows**: the details line now wraps to two lines instead of being cut off at one. Check it on a narrow iPhone.
- **visionOS** is listed in the target but hasn't been built. There's no visionOS simulator installed.
- **The register sorts transactions in memory.** That's fine for personal ledgers; switch to a `@Query` with a predicate if large accounts get slow.
