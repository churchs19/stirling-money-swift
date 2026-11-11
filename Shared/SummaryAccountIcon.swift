import SwiftUI

/// An account's icon from the summary (`WidgetSnapshot.AccountSummary`): an SF Symbol, or a PaymentFont
/// glyph drawn with the bundled font. Used by the widgets and the Watch; the app itself uses `AccountIconView`.
struct SummaryAccountIcon: View {
    let account: WidgetSnapshot.AccountSummary
    /// The SF Symbol's point size. Glyphs are drawn larger, since PaymentFont's logos sit small in the em square.
    var size: CGFloat = 34

    /// Whether the account has an icon to show.
    static func hasIcon(_ account: WidgetSnapshot.AccountSummary) -> Bool {
        account.iconSymbol != nil || account.iconGlyph != nil
    }

    var body: some View {
        if let glyph = account.iconGlyph, PaymentFont.isRegistered {
            Text(glyph)
                .font(.custom(PaymentFont.fontName, size: size * 1.65))
                .lineLimit(1)
                .minimumScaleFactor(0.3)
        } else if let symbol = account.iconSymbol {
            Image(systemName: symbol)
                .font(.system(size: size))
        }
    }
}
