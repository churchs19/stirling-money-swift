import SwiftUI

/// An account's icon: an SF Symbol, or a PaymentFont glyph for names starting with "pf-".
/// Sized to match the given text style, like an SF Symbol in that style.
struct AccountIconView: View {
    let iconName: String
    var textStyle: Font.TextStyle = .body
    /// Enlarges SF Symbols one step, and glyphs to match.
    var isLarge = false

    var body: some View {
        if let glyph = PaymentFont.glyph(forIconName: iconName), PaymentFont.isRegistered {
            Text(glyph.character)
                .font(.custom(PaymentFont.fontName, size: glyphSize, relativeTo: textStyle))
                // Payment logos are much wider than SF Symbols; shrink one to fit its space if needed.
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .accessibilityLabel(glyph.displayName)
        } else {
            Image(systemName: iconName)
                .font(.system(textStyle))
                .imageScale(isLarge ? .large : .medium)
        }
    }

    /// PaymentFont's logos are drawn small within the em square, so they need a larger point size
    /// than the text style to look as big as an SF Symbol beside them.
    private var glyphSize: CGFloat {
        let base: CGFloat = switch textStyle {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
        return base * (isLarge ? 1.6 : 1.4)
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack {
            AccountIconView(iconName: "creditcard", textStyle: .largeTitle, isLarge: true)
            AccountIconView(iconName: "pf-visa", textStyle: .largeTitle, isLarge: true)
            AccountIconView(iconName: "pf-mastercard", textStyle: .largeTitle, isLarge: true)
        }
        HStack {
            AccountIconView(iconName: "creditcard")
            AccountIconView(iconName: "pf-visa")
            AccountIconView(iconName: "pf-paypal")
        }
    }
    .foregroundStyle(.tint)
}
