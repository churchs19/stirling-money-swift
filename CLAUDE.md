# Stirling Money

**Bundle ID:** net.s-church.stirlingmoney
**Target:** iOS 27+, iPadOS 27+, macOS 27+ (one multiplatform target; no visionOS or Mac Catalyst); watchOS 27.2+ for the Watch app
**Plan:** `docs/PLAN.md` — features being re-implemented from the old Windows Phone app, phase status, decisions
**Architecture:** SwiftUI + SwiftData
**Swift version:** 6.2 (app); 6.0 (Watch app, also `MainActor` by default); both widget extensions use the template's Swift 5 mode
**Targets:** `Stirling Money` (app), `StirlingMoneyWidgetsExtension` (widgets, folder `StirlingMoneyWidgets/`), tests, UI tests;
`StirlingMoney Watch App` (watchOS, embedded in the iPhone app only: its dependency and embed phase are filtered to iOS),
`StirlingMoneyWatchWidgetsExtension` (Watch complications, folder `StirlingMoneyWatchWidgets/`), Watch tests and UI tests
**App Group:** `group.net.s-church.stirlingmoney` (app + widgets; on the Watch, Watch app + complications)

## File Structure

```
Stirling Money/
├── Stirling_MoneyApp.swift              # App entry, model container, app lock, widget snapshot on background
├── AppDelegate.swift              # Accepting shared-book invitations (scene delegate on iOS, app delegate on the Mac)
├── Localizable.xcstrings          # String catalog (English); Xcode fills it in when it builds
├── Models/
│   ├── AppSchema.swift            # List of all @Model types for the container
│   ├── Book.swift                 # @Model: a set of accounts (the unit of sharing); + Model.inBook(_:) predicates
│   ├── Account.swift              # @Model: balance, posted balance, next check number, optional icon (+ icon choices)
│   ├── AccentChoice.swift         # Accent color setting: default purple (#7B2CBF, #9D4EDD in dark mode), system (Mac only), or custom; stored in the App Group defaults (StirlingMoneyWidgets/WidgetAccent.swift reads it; keep in step)
│   ├── AccountLayout.swift        # Tiles (default) / list layout for the accounts screen
│   ├── AccountSort.swift          # Name / most-used ordering for the accounts list
│   ├── AccountTransaction.swift   # @Model: register entry + TransactionKind
│   ├── AccountTransaction+Search.swift  # Register search matching
│   ├── Category.swift             # @Model
│   ├── RecurringTransaction.swift # @Model: what to add, its schedule, nextDate (only moves forward), end date or count; problem, upcomingDates
│   ├── RecurrenceSchedule.swift   # Weekly / monthly / twice a month / yearly date math (counted from the start, clamped to short months) + summary text
│   ├── RecurringDraft.swift       # Recurring form fields + validation + save (editing the schedule recomputes nextDate from today)
│   ├── DeepLink.swift             # stirlingmoney://account?id=…, goals, budgets: links from widgets (the widgets build the same URLs); + account(withWidgetID:in:)
│   ├── LaunchMode.swift           # Hosting unit tests / -UITesting (Debug): which store, settings and side effects the app uses
│   ├── Budget.swift               # @Model: current period, amount spent
│   ├── Budget+Summary.swift       # Where a budget stands today, for its card
│   ├── BudgetDraft.swift          # Budget form fields + validation + save
│   ├── BudgetPeriod.swift         # Weekly/monthly/yearly/custom period date math
│   ├── Goal.swift                 # @Model: savings target for one account
│   ├── Reports.swift              # Report calculations (monthly totals, category slices, budget history)
│   ├── GoalDraft.swift            # Goal form fields + validation + save
│   ├── TransactionDraft.swift     # Transaction form fields + validation (saved by Ledger.save)
│   ├── TransactionCSV.swift       # CSV export of every transaction + shareable file
│   └── WidgetSnapshot+Models.swift  # Builds the widget summary from the models (the type itself is in Shared/)
├── Views/
│   ├── RootView.swift             # TabView: Accounts / Budgets / Goals / Reports (sidebar on iPad and Mac)
│   ├── SettingsView.swift         # Sort, accent color, app lock, export, rate; a sheet from the Accounts ⋯ menu, a Settings window (⌘,) on the Mac
│   ├── LockView.swift             # Covers the app while locked
│   ├── AccountsView.swift         # Accounts as tiles or a list (toolbar toggle), total, sort, delete
│   ├── AccountRegisterView.swift  # One account's transactions, balances, search
│   ├── NewAccountView.swift       # Add account sheet
│   ├── EditAccountView.swift      # Edit account sheet (@Bindable)
│   ├── TransactionFormView.swift  # Add/edit transaction sheet for every kind
│   ├── CategoriesView.swift       # Category list: add, rename, delete
│   ├── BudgetsView.swift / BudgetFormView.swift  # Budget cards; add/edit sheet
│   ├── GoalsView.swift / GoalFormView.swift      # Goal cards; add/edit sheet
│   ├── RecurringFormView.swift / RecurringListView.swift  # Recurring add/edit sheet; all-accounts Recurring screen (Accounts ⋯ menu)
│   ├── Reports/                   # ReportsView list + one view per Swift Charts report; ReportSupport.swift
│   ├── PreviewData.swift          # ModelContainer.preview sample data (DEBUG only)
│   └── Components/                # BookSwitcher (.bookSwitcher toolbar menu), AmountText, CurrencyField, TransactionRow, BudgetRow, GoalRow, PostedCheckmark (+ .posted toggle style), AccountTile, AccountIconPicker, AccountIconView (SF Symbol or PaymentFont glyph), NavigationRow, RecurringRow (+ recurringRowActions: Edit, Skip Next, Add Now, Delete)
├── Managers/
│   ├── Ledger.swift               # Create/edit/delete transactions and transfers; categories (per book)
│   ├── Books.swift                # prepare (first book, data from before books), current book, create, delete
│   ├── AppLock.swift              # Face ID / Touch ID / passcode lock (LocalAuthentication)
│   ├── WidgetSnapshotWriter.swift # Writes the snapshot to the App Group, reloads widgets, sends it to the Watch
│   ├── WatchSync.swift            # iPhone only: WCSession; sends the snapshot as application context, answers Watch requests
│   ├── Sync/                      # CloudRecords (each model ↔ CKRecord, encrypted values, zones), RecordImporter,
│   │                              #   RecordMerger (three-way conflict merge), SyncProcessor (history out, fetched in,
│   │                              #   results, shares; testable), SyncCoordinator (private + shared CKSyncEngines, share,
│   │                              #   stop sharing, accept; never under tests or sample data)
│   ├── RecurringScheduler.swift   # addDue (adds due occurrences through Ledger, catching up), addNow, skipNext, nextDueDate
│   └── RecurringRunner.swift      # When addDue runs: launch, active, midnight, hourly + wake on the Mac, BGAppRefreshTask on iOS
└── Extensions/
    ├── Decimal+Money.swift        # Parsing typed amounts (.localCurrency itself is in Shared/)
    ├── Color+Chart.swift          # ChartPalette: validated chart colors; assign slots in order, never cycle
    ├── View+Accent.swift          # .appAccent() tint for each scene + \.appAccent environment value
    ├── View+BookEditing.swift     # \.canEditBook: false in a View Only book (RootView sets it; sheets inherit it)
    └── View+Platform.swift        # Touch-only modifiers that do nothing on macOS
Stirling MoneyTests/               # Swift Testing; in-memory container + UTC calendar in TestSupport.swift
Stirling MoneyUITests/             # XCUITest on the iPhone simulator with -UITesting; finds controls by accessibility identifier
StirlingMoney Watch App/           # watchOS app (read-only): Accounts / Budgets / Goals pages; WatchStore receives the iPhone's summary
StirlingMoney Watch AppTests/      # Swift Testing for WatchStore (run on a Watch simulator)
StirlingMoney Watch AppUITests/    # XCUITest smoke test of the three pages, with the Watch app's -UseSampleData
StirlingMoneyWatchWidgets/         # Watch complications: Balance, Goal and Budget (circular, rectangular, inline, corner); read the summary the Watch app saves; choices come from recommendations()
Shared/                            # In the app, the widgets, the Watch app and the complications:
│                                  #   WidgetSnapshot (the JSON summary), WatchMessage (WatchConnectivity keys), .localCurrency,
│                                  #   PaymentFont (116 glyphs generated from its CSS; "pf-…" icon names; registers the font at run time),
│                                  #   SummaryAccountIcon (a summary account's icon, for widgets and the Watch),
│                                  #   BudgetSummaryCard (a summary budget laid out like BudgetRow: full, dense, compact; + periodText, budgetsToList),
│                                  #   WidgetChoice / BalanceChoice (which item a widget or complication shows, or why none),
│                                  #   WidgetSnapshot+Projection (upcoming recurring occurrences, projected(on:), timelineDates),
│                                  #   DateInterval.formattedDays (budget period dates for the app, widgets and Watch),
│                                  #   WidgetIntents (account, goal and budget pickers for the iPhone widgets and the complications),
│                                  #   Fonts/ (paymentfont-webfont.ttf + its MIT license, bundled into all four)
StirlingMoneyWidgets/              # Widget extension: Balance, Goal and Budget (configured with App Intents) and All Budgets (BudgetListWidget, static)
```

Widgets can't open the SwiftData store; the app writes `WidgetSnapshot.json` to the App Group shortly after each
save (plus at launch, on going to the background and on quitting the Mac app), and the widgets read it. `WidgetSnapshot` lives in `Shared/`,
which belongs to all four app and widget targets; code there must compile for each of them (no SwiftData models, no app-only helpers).

Budget figures in the summary are for the period that was current when the app wrote it (budgets outside an active period
are left out). Widgets and complications can't work out a new period, so after `periodEnd` they show "Open Stirling Money to
update" (`BudgetSummary.isCurrent(on:)`), and their timelines reload at the earliest `periodEnd` shown.

Recurring transactions are added by `RecurringScheduler.addDue` as ordinary unposted transactions (through `Ledger`, linked
by `AccountTransaction.recurrence`), moving each rule's `nextDate` on in the same save so nothing is added twice. `RecurringRunner`
calls it at launch, when the app becomes active, at midnight, hourly and on wake on the Mac, and in a `BGAppRefreshTask` on iOS
(iOS picks the time). Until the app runs, the summary lists the next 45 days of occurrences (`upcoming`), and every widget,
complication and Watch page shows `projected(on:)` that day: balances (not posted), goals and budgets by the same rules as
`Budget.spent` and `Goal.progress` (`BudgetSummary.counts`, `GoalSummary.progress`). Timelines get an entry per due day
(`timelineDates`). A test compares the projection with what `addDue` really adds; keep the two in step. Nothing runs under
`LaunchMode.isTesting`. With iCloud sync, two devices could add the same occurrence: de-duplicate by rule and date then.

The Watch can't read the iPhone's store or App Group either, and there's no iCloud sync yet, so the iPhone sends it the same summary
over WatchConnectivity (`WatchSync`, iPhone only):
- Each time `WidgetSnapshotWriter` writes a changed summary (after saves, at launch, on going to the background), it sends it as the
  application context. The system keeps only the latest and delivers it when the Watch app next runs.
- When the Watch app comes to the front it asks for a fresh one with `sendMessage` (keys in `Shared/WatchMessage.swift`); iOS can
  wake the iPhone app in the background to answer with the saved file.
- `WatchStore` keeps a summary only if it's at least as new as the one it has, saves it to the Watch's own App Group container
  for the complications, and reloads their timelines.
- On watchOS, complications aren't configured with the intent's parameters: the watch face editor lists the presets from each
  provider's `recommendations()` (the total, each account, each goal), which the system caches. `WatchStore` calls
  `invalidateConfigurationRecommendations()` at launch and when accounts, goals or budgets change; without it the list stays as first made.
- The Watch app asks again when its session finishes activating and when the iPhone becomes reachable: the request when the app
  comes to the front usually runs before activation and is skipped.
- WatchConnectivity calls delegates and reply handlers on its own queue: keep them `nonisolated`/`@Sendable` and hop to the main
  actor for state (a main-actor closure there crashes).

The project uses file-system synchronized folders: new files in these folders are picked up automatically.
The app target defaults to `MainActor` isolation; mark plain value types `nonisolated` when `@Model` code uses them.

## Build & Test — Always Use MCP

Prefer MCP tools over raw shell commands for ALL build operations:

- **Build**: `build_sim` / `build_device` (NOT `xcodebuild` via Bash)
- **Test**: `test_sim` / `test_device` (NOT `xcodebuild test` via Bash)
- **Simulators**: `list_sims`, `boot_sim`, `open_sim` (NOT `xcrun simctl` via Bash)
- **Debug**: `debug_attach_sim`, `debug_stack`, `debug_variables`
- **Apple docs**: `DocumentationSearch` (NOT WebSearch for Apple APIs)
- **Swift verification**: `ExecuteSnippet` (NOT `swift` via Bash)
- **Previews**: `RenderPreview` for headless SwiftUI verification

## Tests

- **Unit tests** (Swift Testing, `Stirling MoneyTests`) run inside the app; `LaunchMode.isHostingUnitTests` gives it an empty
  in-memory store, no screens, and no widget summary or Watch. Build models in `makeInMemoryContainer()` and use `utc`/`day(_:_:_:)`.
  Code that depends on the system takes it as a parameter so tests can replace it: `AppLock(authenticator:)`, the widget pickers'
  `summary`, `WidgetSnapshot.load(from:)`, `needsWrite(over:)`, and an optional `locale` for money formatting and parsing.
- **UI tests** launch with `-UITesting` (sample data, settings in a fresh `LaunchMode.settings` store, no widget summary or Watch)
  and US English. Give controls they drive an `.accessibilityIdentifier` (`addAccount`, `account.<name>`, `save`, …; `CurrencyField`
  takes `identifier:`). SwiftUI folds amounts into their row's label ("Total, $19,660.73"), so check labels, not text elements.
  Items in a toolbar's ⋯ (overflow) menu lose their identifiers: find them by label (`menuItem(_:)`).
- Don't wrap a whole screen in a `TimelineView` to refresh it: it kept the Watch app from going idle and UI tests crawled. Move a
  date on when the app becomes active instead (`WatchStore.showToday()`).
- **Watch UI tests** launch the Watch app with `-UseSampleData` (`WidgetSnapshot.sample`, no WatchConnectivity).

XcodeBuildMCP only drives iOS simulators. For the Watch targets and their tests, and for Mac builds, use `xcodebuild` with a
watchOS simulator or `platform=macOS` destination (`-allowProvisioningUpdates` lets automatic signing create the Watch and Mac
profiles). Debug devices, including a real Watch, must be registered with the team before a development build will install.

MCP returns structured JSON. Bash returns unstructured text.
Structured data means fewer tokens consumed and better error diagnosis.

## SwiftData Relationships

| From | To | Delete rule |
|---|---|---|
| Account.transactions | AccountTransaction.account | cascade |
| Account.goals | Goal.account | cascade |
| Category.transactions | AccountTransaction.category | nullify |
| Category.budgets | Budget.category | cascade (a budget without its category would silently become "all spending") |
| AccountTransaction.incomingHalf | AccountTransaction.outgoingHalf | nullify (transfer pair) |
| Account.recurringTransactions | RecurringTransaction.account | cascade |
| Account.recurringTransfersIn | RecurringTransaction.otherAccount | nullify (the rule stops and shows a problem) |
| Category.recurringTransactions | RecurringTransaction.category | nullify |
| RecurringTransaction.transactions | AccountTransaction.recurrence | nullify (added transactions stay when the rule is deleted) |

- Every `ModelConfiguration` passes `cloudKitDatabase: .none`: our own `SyncCoordinator` syncs the store, and the
  default would start SwiftData's built-in mirroring too, now that the app has an iCloud container.
- Keep models CloudKit-compatible so sync can be turned on later without a migration: every stored property has a default or is optional, every relationship is optional, no `@Attribute(.unique)`.
- Declare `inverse:` on one side only.
- A property can't be its own inverse (circular macro error), which is why transfers use two properties. Read `transferCounterpart`.
- Money is `Decimal`, never `Double`. `AccountTransaction.amount` is signed: negative leaves the account.
- Enums are stored as raw-value strings (`kindRawValue`, `periodRawValue`) with a computed typed property, so they work in `#Predicate`.
- Create and delete transactions through `Ledger`, not directly, so signs stay right and transfer pairs are created and deleted together.
- A book shared as View Only (`Book.canEdit` false) can't be changed: read `@Environment(\.canEditBook)` and hide or
  disable every control that edits (toolbar adds, row taps that open forms, swipe actions, context menus, toggles).
  Recurring transactions aren't added there, and sync drops any change to it (`SyncProcessor.withoutGoneBooks`).
- Everything belongs to a `Book`: set `book` when creating a model (`Ledger` and the drafts take it from the account),
  and filter every `@Query` and fetch with `Model.inBook(book)`. The current book's `syncID` is in settings
  (`Books.currentKey`); screens get the book in their initializer. Every model has a `syncID` (`preserveValueOnDeletion`).
- Insert a model into the context before setting its relationships.

## Rules

- NEVER modify .pbxproj or project.xcproj by hand. Exception (approved for Phase 6): Xcode's own tools
  (`XcodeNewTarget`, `AddInfoPlist`, `AddEntitlement`) were used to add the widget target, App Group and
  `NSFaceIDUsageDescription`. Approved for Phase 7: the Watch app and complications targets, their App Group, display
  names and Swift version, and (made by hand in Xcode) the `Shared/` folder membership and the Watch app's iOS platform
  filters. Approved for Phase 10 (made with `AddInfoPlist`): `UIBackgroundModes` = `fetch` and
  `BGTaskSchedulerPermittedIdentifiers` = `net.s-church.stirlingmoney.recurring` on the app target, which put them in
  `Stirling-Money-Info.plist` (merged with the generated Info.plist keys). Approved for Phase 11 (made with
  `AddEntitlement` and `AddInfoPlist`): iCloud (CloudKit, container `iCloud.net.s-church.stirlingmoney`), Push
  Notifications (`aps-environment`), `remote-notification` in `UIBackgroundModes`, and `CKSharingSupported`.
  Ask before any further project change.
- NEVER use ObservableObject — use @Observable
- NEVER use NavigationView — use NavigationStack
- @Model classes are already Observable — do not add @Observable macro
- Use @Bindable for form bindings to model properties
- Code must build for macOS as well as iOS. Don't call iOS-only modifiers (`textInputAutocapitalization`, `keyboardType`, `navigationBarTitleDisplayMode`) directly; use the helpers in `View+Platform.swift` or `#if os(macOS)`. Give swipe actions a matching `.contextMenu` for mouse users. Wrap context-menu actions that show a sheet, alert or dialog in `afterMenuCloses { }` (the Mac drops presentations started while the menu closes), and use `NavigationRow` for list rows that push onto a `NavigationStack(path:)`.
- Don't name `Color.accentColor` in views: it's always the default purple. Use `.tint` styles or `@Environment(\.appAccent)`, which follow the accent color chosen in Settings.
- Debug builds launched with `-UseSampleData` use the in-memory preview data instead of the real store; `-UITesting` does too,
  with fresh settings. Read settings through `@AppStorage` (the app sets `.defaultAppStorage(LaunchMode.settings)`) or
  `LaunchMode.settings`, never `UserDefaults.standard` directly, so UI tests start clean.

