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
│   ├── Item.swift             # @Model: Initial model from templte
├── Views/
│   ├── ContentView.swift  # Initial view from template
├── Managers/
└── Extensions/
```

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

## Rules

- NEVER modify .pbxproj or project.xcproj
- NEVER use ObservableObject — use @Observable
- NEVER use NavigationView — use NavigationStack
- @Model classes are already Observable — do not add @Observable macro
- Use @Bindable for form bindings to model properties

