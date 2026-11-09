import SwiftUI

/// Icons to choose from for an account: "None", SF Symbols, then PaymentFont's payment logos.
struct AccountIconPicker: View {
    @Binding var iconName: String?

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                choice(nil, label: String(localized: "No icon"))
                ForEach(Account.iconChoices, id: \.self) { name in
                    choice(name, label: name.replacingOccurrences(of: ".", with: " "))
                }
            }

            Text("Payment")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(PaymentFont.glyphs) { glyph in
                    choice(glyph.id, label: glyph.displayName)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func choice(_ name: String?, label: String) -> some View {
        let isSelected = iconName == name
        return Button {
            iconName = name
        } label: {
            Group {
                if let name {
                    AccountIconView(iconName: name, textStyle: .title3)
                } else {
                    Image(systemName: "nosign")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.title3)
            .frame(width: 44, height: 44)
            .help(label)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var iconName: String? = "banknote"
    Form {
        Section("Icon") {
            AccountIconPicker(iconName: $iconName)
        }
    }
    .formStyle(.grouped)
    .frame(width: 560, height: 900)
}
