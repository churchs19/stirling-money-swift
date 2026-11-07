# Stirling Money

**Bundle ID:** net.s-church.stirlingmoney
**Target:** iOS 27+, iPadOS 27+, macOS 27+ (one multiplatform target; visionOS is also listed but unverified)
**Plan:** `docs/PLAN.md` — features being re-implemented from the old Windows Phone app, phase status, decisions
**Architecture:** SwiftUI + SwiftData
**Swift version:** 6.2 (app); the widget extension uses the template's Swift 5 mode
**Targets:** `Stirling Money` (app), `StirlingMoneyWidgetsExtension` (widgets, folder `StirlingMoneyWidgets/`), tests, UI tests
**App Group:** `group.net.s-church.stirlingmoney` (app + widgets)
**iCloud:** CloudKit container `iCloud.net.s-church.stirlingmoney`, private database; SwiftData syncs the whole store (see below). **Currently off**: the signing team is a free personal team, which can't have iCloud/push, so the entitlements are removed and `SyncMonitor.isEnabled` is `false`. Turn both on together (README → iCloud); requesting a CloudKit container without the entitlement can crash.

## File Structure

```
Stirling Money/
├── Stirling_MoneyApp.swift              # App entry, model container, app lock, widget snapshot on background
├── Localizable.xcstrings          # String catalog (English); Xcode fills it in when it builds
├── Models/
│   ├── AppSchema.swift            # List of all @Model types for the container
│   ├── Account.swift              # @Model: balance, posted balance, next check number
│   ├── AccountSort.swift          # Name / most-used ordering for the accounts list
│   ├── AccountTransaction.swift   # @Model: register entry + TransactionKind
│   ├── AccountTransaction+Search.swift  # Register search matching
│   ├── Category.swift             # @Model
│   ├── Budget.swift               # @Model: current period, amount spent
│   ├── Budget+Summary.swift       # Where a budget stands today, for its card
│   ├── BudgetDraft.swift          # Budget form fields + validation + save
│   ├── BudgetPeriod.swift         # Weekly/monthly/yearly/custom period date math
│   ├── Goal.swift                 # @Model: savings target for one account
│   ├── Reports.swift              # Report calculations (monthly totals, category slices, budget history)
│   ├── GoalDraft.swift            # Goal form fields + validation + save
│   ├── TransactionDraft.swift     # Transaction form fields + validation (saved by Ledger.save)
│   ├── TransactionCSV.swift       # CSV export of every transaction + shareable file
│   └── WidgetSnapshot.swift       # JSON the widgets read (a copy lives in StirlingMoneyWidgets/; keep in step)
├── Views/
│   ├── RootView.swift             # TabView: Accounts / Budgets / Goals / Reports / Settings (sidebar on iPad and Mac)
│   ├── SettingsView.swift         # Sort, app lock, export, rate; a Settings window on the Mac
│   ├── LockView.swift             # Covers the app while locked
│   ├── AccountsView.swift         # Accounts list with total, sort, delete
│   ├── AccountRegisterView.swift  # One account's transactions, balances, search
│   ├── NewAccountView.swift       # Add account sheet
│   ├── EditAccountView.swift      # Edit account sheet (@Bindable)
│   ├── TransactionFormView.swift  # Add/edit transaction sheet for every kind
│   ├── CategoriesView.swift       # Category list: add, rename, delete
│   ├── BudgetsView.swift / BudgetFormView.swift  # Budget cards; add/edit sheet
│   ├── GoalsView.swift / GoalFormView.swift      # Goal cards; add/edit sheet
│   ├── Reports/                   # ReportsView list + one view per Swift Charts report; ReportSupport.swift
│   ├── PreviewData.swift          # ModelContainer.preview sample data (DEBUG only)
│   └── Components/                # AmountText, CurrencyField, TransactionRow, BudgetRow, GoalRow, PostedCheckmark (+ .posted toggle style)
├── Managers/
│   ├── Ledger.swift               # Create/edit/delete transactions and transfers; categories
│   ├── AppLock.swift              # Face ID / Touch ID / passcode lock (LocalAuthentication)
│   ├── SyncMonitor.swift          # iCloud account status; after imports, merges duplicate categories, refreshes widgets
│   ├── CategoryMerger.swift       # Combines same-named categories (oldest createdAt wins)
│   └── WidgetSnapshotWriter.swift # Writes the snapshot to the App Group and reloads widgets
└── Extensions/
    ├── Decimal+Money.swift        # .localCurrency format, parsing typed amounts
    ├── Color+Chart.swift          # ChartPalette: validated chart colors; assign slots in order, never cycle
    └── View+Platform.swift        # Touch-only modifiers that do nothing on macOS
Stirling MoneyTests/               # Swift Testing; in-memory container + UTC calendar in TestSupport.swift
StirlingMoneyWidgets/              # Widget extension: Balance and Goal widgets, configured with App Intents
```

Widgets can't open the SwiftData store; the app writes `WidgetSnapshot.json` to the App Group shortly after each
save (plus on going to the background and on quitting the Mac app), and the widgets read it. Change both copies of `WidgetSnapshot` together.

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

- Models must stay CloudKit-compatible or the store won't open with sync: every stored property has a default or is optional, every relationship is optional, no `@Attribute(.unique)`.
- Uniqueness can't be enforced, so duplicates arrive from other devices. `CategoryMerger` merges same-named categories after each import; anything else that must be unique needs the same treatment.
- Declare `inverse:` on one side only.
- A property can't be its own inverse (circular macro error), which is why transfers use two properties. Read `transferCounterpart`.
- Money is `Decimal`, never `Double`. `AccountTransaction.amount` is signed: negative leaves the account.
- Enums are stored as raw-value strings (`kindRawValue`, `periodRawValue`) with a computed typed property, so they work in `#Predicate`.
- Create and delete transactions through `Ledger`, not directly, so signs stay right and transfer pairs are created and deleted together.
- Insert a model into the context before setting its relationships.

## CloudKit Sync — Schema Rules

The store syncs to CloudKit, whose **production schema can only grow** once deployed.

- After the first App Store / TestFlight release, change models only by **adding** stored properties, each optional or with a default, or adding new `@Model` types (also add them to `AppSchema`).
- **Never** rename or remove a stored property, change its type, rename a model, or change `@Relationship` inverses. Add a new property and stop using the old one instead. (`@Attribute(originalName:)` doesn't help: CloudKit still sees a new field.)
- Computed properties and anything not stored are free to change.
- Debug builds create schema changes in the CloudKit **development** environment automatically. Before releasing a build that adds fields, deploy the schema to **production** in the CloudKit Console, or sync silently stops for users. Say so in the summary whenever a change adds or alters a stored property.
- Sample-data runs (`-UseSampleData`) are in memory and never sync.

## Rules

- NEVER modify .pbxproj or project.xcproj by hand. Exception (approved for Phase 6): Xcode's own tools
  (`XcodeNewTarget`, `AddInfoPlist`, `AddEntitlement`) were used to add the widget target, App Group and
  `NSFaceIDUsageDescription`, and later the remote-notification background mode (`Stirling-Money-Info.plist`) for
  CloudKit sync. The iCloud and push entitlements were added and then removed again (personal team). Ask before any
  further project change.
- NEVER use ObservableObject — use @Observable
- NEVER use NavigationView — use NavigationStack
- @Model classes are already Observable — do not add @Observable macro
- Use @Bindable for form bindings to model properties
- Code must build for macOS as well as iOS. Don't call iOS-only modifiers (`textInputAutocapitalization`, `keyboardType`, `navigationBarTitleDisplayMode`) directly; use the helpers in `View+Platform.swift` or `#if os(macOS)`. Give swipe actions a matching `.contextMenu` for mouse users. Wrap context-menu actions that show a sheet, alert or dialog in `afterMenuCloses { }` (the Mac drops presentations started while the menu closes), and use `NavigationRow` for list rows that push onto a `NavigationStack(path:)`.
- Debug builds launched with `-UseSampleData` use the in-memory preview data instead of the real store.

