import SwiftUI

/// The posted indicator used throughout the app: an empty circle, or a green circle with a checkmark.
struct PostedCheckmark: View {
    let isPosted: Bool

    var body: some View {
        Image(systemName: isPosted ? "checkmark.circle.fill" : "circle")
            .imageScale(.large)
            .foregroundStyle(isPosted ? Color.green : Color.secondary)
    }
}

/// Shows a toggle as the posted checkmark followed by its label, matching the register rows.
/// The whole row is tappable or clickable.
struct PostedToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                PostedCheckmark(isPosted: configuration.isOn)
                configuration.label
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

extension ToggleStyle where Self == PostedToggleStyle {
    static var posted: PostedToggleStyle {
        PostedToggleStyle()
    }
}

#Preview {
    @Previewable @State var isPosted = true
    Form {
        Toggle("Posted", isOn: $isPosted)
            .toggleStyle(.posted)
    }
}
