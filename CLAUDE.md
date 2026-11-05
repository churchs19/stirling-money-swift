# Stirling Money

**Bundle ID:** net.s-church.stirlingmoney
**Target:** iOS 27+
**Architecture:** SwiftUI + SwiftData
**Swift version:** 6.2

## File Structure

```
Stirling Money/
├── Stirling_MoneyApp.swift              # App entry, model container
├── Models/
│   ├── AppSchema.swift            # List of all @Model types for the container
│   ├── Account.swift              # @Model: balance, posted balance, next check number
│   ├── AccountTransaction.swift   # @Model: register entry + TransactionKind
│   ├── Category.swift             # @Model
│   ├── Budget.swift               # @Model: current period, amount spent
│   ├── BudgetPeriod.swift         # Weekly/monthly/yearly/custom period date math
│   └── Goal.swift                 # @Model: savings target for one account
├── Views/
│   ├── AccountsView.swift         # Accounts list (root view)
│   └── NewAccountView.swift       # Add account sheet
├── Managers/
│   └── Ledger.swift               # Create/delete transactions and transfers
└── Extensions/
Stirling MoneyTests/               # Swift Testing; in-memory container + UTC calendar in TestSupport.swift
```

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

- Keep models CloudKit-compatible so sync can be turned on later without a migration: every stored property has a default or is optional, every relationship is optional, no `@Attribute(.unique)`.
- Declare `inverse:` on one side only.
- A property can't be its own inverse (circular macro error), which is why transfers use two properties. Read `transferCounterpart`.
- Money is `Decimal`, never `Double`. `AccountTransaction.amount` is signed: negative leaves the account.
- Enums are stored as raw-value strings (`kindRawValue`, `periodRawValue`) with a computed typed property, so they work in `#Predicate`.
- Create and delete transactions through `Ledger`, not directly, so signs stay right and transfer pairs are created and deleted together.
- Insert a model into the context before setting its relationships.

## Rules

- NEVER modify .pbxproj or project.xcproj
- NEVER use ObservableObject — use @Observable
- NEVER use NavigationView — use NavigationStack
- @Model classes are already Observable — do not add @Observable macro
- Use @Bindable for form bindings to model properties

