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

## Build & Test

```bash
xcodebuild -scheme 'Stirling Money' -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme 'Stirling Money' -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## SwiftData Relationships

## Rules

- NEVER modify .pbxproj or project.xcproj
- NEVER use ObservableObject — use @Observable
- NEVER use NavigationView — use NavigationStack
- @Model classes are already Observable — do not add @Observable macro
- Use @Bindable for form bindings to model properties

