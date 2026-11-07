import SwiftUI

/// A list row that opens `value` in the enclosing `NavigationStack(path:)`.
///
/// On iOS and iPadOS it's an ordinary `NavigationLink`. On the Mac it's a plain button that appends
/// to the path, with a chevron: `NavigationLink` rows in a `List` didn't respond to clicks there.
struct NavigationRow<Value: Hashable, Label: View>: View {
    let value: Value
    @Binding var path: [Value]
    @ViewBuilder var label: Label

    var body: some View {
        #if os(macOS)
            Button {
                path.append(value)
            } label: {
                HStack {
                    label
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        #else
            NavigationLink(value: value) {
                label
            }
        #endif
    }
}
