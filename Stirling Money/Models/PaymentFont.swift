import CoreText
import Foundation

/// PaymentFont: payment-brand and currency glyphs, offered as account icons.
///
/// Font and names from https://github.com/AlexanderPoellmann/PaymentFont (MIT License,
/// © 2017 Alexander Manfred Pöllmann; see `Resources/Fonts/PaymentFont-LICENSE.txt`).
/// The table below was generated from that repository's `css/paymentfont.css`.
/// An account stores a glyph as its CSS class name, such as "pf-visa", in `Account.iconName`.
nonisolated enum PaymentFont {
    /// The font's PostScript name, for `Font.custom`.
    static let fontName = "paymentfont-webfont"
    static let iconNamePrefix = "pf-"

    struct Glyph: Identifiable, Hashable {
        /// The CSS class name without "pf-", such as "visa".
        let name: String
        let codePoint: UInt32
        /// A readable name, used by VoiceOver.
        let displayName: String

        /// What `Account.iconName` stores, such as "pf-visa".
        var id: String {
            PaymentFont.iconNamePrefix + name
        }

        /// The glyph's character in the font.
        var character: String {
            Unicode.Scalar(codePoint).map { String(Character($0)) } ?? ""
        }
    }

    /// The glyph an icon name refers to, or nil if it's an SF Symbol name.
    static func glyph(forIconName iconName: String) -> Glyph? {
        guard iconName.hasPrefix(iconNamePrefix) else { return nil }
        return glyphsByID[iconName]
    }

    private static let glyphsByID = Dictionary(uniqueKeysWithValues: glyphs.map { ($0.id, $0) })

    /// Registers the bundled font with this process. Runs once, the first time it's read;
    /// registering at run time means no Info.plist entry is needed. False if the font is missing.
    static let isRegistered: Bool = {
        guard let url = Bundle.main.url(forResource: fontName, withExtension: "ttf")
            ?? Bundle.main.url(forResource: fontName, withExtension: "ttf", subdirectory: "Fonts")
        else { return false }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            return true
        }
        // Already registered (for example by a preview) also means it's usable.
        let font = CTFontCreateWithName(fontName as CFString, 12, nil)
        return (CTFontCopyPostScriptName(font) as String) == fontName
    }()

    static let glyphs: [Glyph] = [
        Glyph(name: "amazon", codePoint: 0xF000, displayName: "Amazon"),
        Glyph(name: "american-express", codePoint: 0xF001, displayName: "American Express"),
        Glyph(name: "american-express-alt", codePoint: 0xF002, displayName: "American Express (Alternate)"),
        Glyph(name: "atm", codePoint: 0xF003, displayName: "ATM"),
        Glyph(name: "bankomat", codePoint: 0xF004, displayName: "Bankomat"),
        Glyph(name: "bank-transfer", codePoint: 0xF005, displayName: "Bank Transfer"),
        Glyph(name: "bitcoin", codePoint: 0xF006, displayName: "Bitcoin"),
        Glyph(name: "bitcoin-sign", codePoint: 0xF007, displayName: "Bitcoin Sign"),
        Glyph(name: "braintree", codePoint: 0xF008, displayName: "Braintree"),
        Glyph(name: "btc", codePoint: 0xF009, displayName: "BTC"),
        Glyph(name: "card", codePoint: 0xF00A, displayName: "Card"),
        Glyph(name: "carta-si", codePoint: 0xF00B, displayName: "Carta Si"),
        Glyph(name: "cash", codePoint: 0xF00C, displayName: "Cash"),
        Glyph(name: "cash-on-delivery", codePoint: 0xF00D, displayName: "Cash On Delivery"),
        Glyph(name: "cb", codePoint: 0xF00E, displayName: "CB"),
        Glyph(name: "cirrus", codePoint: 0xF00F, displayName: "Cirrus"),
        Glyph(name: "cirrus-alt", codePoint: 0xF010, displayName: "Cirrus (Alternate)"),
        Glyph(name: "clickandbuy", codePoint: 0xF011, displayName: "ClickandBuy"),
        Glyph(name: "credit-card", codePoint: 0xF012, displayName: "Credit Card"),
        Glyph(name: "diners", codePoint: 0xF013, displayName: "Diners"),
        Glyph(name: "discover", codePoint: 0xF014, displayName: "Discover"),
        Glyph(name: "ec", codePoint: 0xF015, displayName: "EC"),
        Glyph(name: "eps", codePoint: 0xF016, displayName: "EPS"),
        Glyph(name: "eur", codePoint: 0xF017, displayName: "EUR"),
        Glyph(name: "facture", codePoint: 0xF018, displayName: "Facture"),
        Glyph(name: "fattura", codePoint: 0xF019, displayName: "Fattura"),
        Glyph(name: "flattr", codePoint: 0xF01A, displayName: "Flattr"),
        Glyph(name: "giropay", codePoint: 0xF01B, displayName: "giropay"),
        Glyph(name: "google-wallet", codePoint: 0xF01C, displayName: "Google Wallet"),
        Glyph(name: "google-wallet-alt", codePoint: 0xF01D, displayName: "Google Wallet (Alternate)"),
        Glyph(name: "gbp", codePoint: 0xF01E, displayName: "GBP"),
        Glyph(name: "gratipay", codePoint: 0xF01F, displayName: "Gratipay"),
        Glyph(name: "ideal", codePoint: 0xF020, displayName: "iDEAL"),
        Glyph(name: "ils", codePoint: 0xF021, displayName: "ILS"),
        Glyph(name: "inr", codePoint: 0xF022, displayName: "INR"),
        Glyph(name: "invoice", codePoint: 0xF023, displayName: "Invoice"),
        Glyph(name: "invoice-sign", codePoint: 0xF024, displayName: "Invoice Sign"),
        Glyph(name: "invoice-sign-alt", codePoint: 0xF025, displayName: "Invoice Sign (Alternate)"),
        Glyph(name: "invoice-sign-alt-o", codePoint: 0xF026, displayName: "Invoice Sign (Alternate) Outline"),
        Glyph(name: "invoice-sign-o", codePoint: 0xF027, displayName: "Invoice Sign Outline"),
        Glyph(name: "jcb", codePoint: 0xF028, displayName: "JCB"),
        Glyph(name: "jpy", codePoint: 0xF029, displayName: "JPY"),
        Glyph(name: "krw", codePoint: 0xF02A, displayName: "KRW"),
        Glyph(name: "maestro", codePoint: 0xF02B, displayName: "Maestro"),
        Glyph(name: "maestro-alt", codePoint: 0xF02C, displayName: "Maestro (Alternate)"),
        Glyph(name: "mastercard", codePoint: 0xF02D, displayName: "Mastercard"),
        Glyph(name: "mastercard-alt", codePoint: 0xF02E, displayName: "Mastercard (Alternate)"),
        Glyph(name: "mastercard-securecode", codePoint: 0xF02F, displayName: "Mastercard SecureCode"),
        Glyph(name: "ogone", codePoint: 0xF030, displayName: "Ogone"),
        Glyph(name: "paybox", codePoint: 0xF031, displayName: "Paybox"),
        Glyph(name: "paylife", codePoint: 0xF032, displayName: "PayLife"),
        Glyph(name: "paypal", codePoint: 0xF033, displayName: "PayPal"),
        Glyph(name: "paypal-alt", codePoint: 0xF034, displayName: "PayPal (Alternate)"),
        Glyph(name: "paysafecard", codePoint: 0xF035, displayName: "paysafecard"),
        Glyph(name: "postepay", codePoint: 0xF036, displayName: "Postepay"),
        Glyph(name: "quick", codePoint: 0xF037, displayName: "Quick"),
        Glyph(name: "rechnung", codePoint: 0xF038, displayName: "Rechnung"),
        Glyph(name: "ripple", codePoint: 0xF039, displayName: "Ripple"),
        Glyph(name: "rub", codePoint: 0xF03A, displayName: "RUB"),
        Glyph(name: "skrill", codePoint: 0xF03B, displayName: "Skrill"),
        Glyph(name: "sofort", codePoint: 0xF03C, displayName: "Sofort"),
        Glyph(name: "square", codePoint: 0xF03D, displayName: "Square"),
        Glyph(name: "stripe", codePoint: 0xF03E, displayName: "Stripe"),
        Glyph(name: "truste", codePoint: 0xF03F, displayName: "TRUSTe"),
        Glyph(name: "try", codePoint: 0xF040, displayName: "TRY"),
        Glyph(name: "unionpay", codePoint: 0xF041, displayName: "UnionPay"),
        Glyph(name: "usd", codePoint: 0xF042, displayName: "USD"),
        Glyph(name: "verified-by-visa", codePoint: 0xF043, displayName: "Verified By Visa"),
        Glyph(name: "verisign", codePoint: 0xF044, displayName: "VeriSign"),
        Glyph(name: "visa", codePoint: 0xF045, displayName: "Visa"),
        Glyph(name: "visa-electron", codePoint: 0xF046, displayName: "Visa Electron"),
        Glyph(name: "western-union", codePoint: 0xF047, displayName: "Western Union"),
        Glyph(name: "western-union-alt", codePoint: 0xF048, displayName: "Western Union (Alternate)"),
        Glyph(name: "wirecard", codePoint: 0xF049, displayName: "Wirecard"),
        Glyph(name: "sepa", codePoint: 0xF04A, displayName: "SEPA"),
        Glyph(name: "sepa-alt", codePoint: 0xF04B, displayName: "SEPA (Alternate)"),
        Glyph(name: "apple-pay", codePoint: 0xF04C, displayName: "Apple Pay"),
        Glyph(name: "interac", codePoint: 0xF04D, displayName: "Interac"),
        Glyph(name: "paymill", codePoint: 0xF04E, displayName: "PAYMILL"),
        Glyph(name: "dankort", codePoint: 0xF04F, displayName: "Dankort"),
        Glyph(name: "bancontact-mister-cash", codePoint: 0xF050, displayName: "Bancontact Mister Cash"),
        Glyph(name: "moip", codePoint: 0xF051, displayName: "MOIP"),
        Glyph(name: "pagseguro", codePoint: 0xF052, displayName: "PagSeguro"),
        Glyph(name: "cash-on-pickup", codePoint: 0xF053, displayName: "Cash On Pickup"),
        Glyph(name: "sage", codePoint: 0xF054, displayName: "Sage"),
        Glyph(name: "elo", codePoint: 0xF055, displayName: "ELO"),
        Glyph(name: "elo-alt", codePoint: 0xF056, displayName: "ELO (Alternate)"),
        Glyph(name: "payu", codePoint: 0xF057, displayName: "PayU"),
        Glyph(name: "mercado-pago", codePoint: 0xF058, displayName: "Mercado Pago"),
        Glyph(name: "mercado-pago-sign", codePoint: 0xF059, displayName: "Mercado Pago Sign"),
        Glyph(name: "payshop", codePoint: 0xF05A, displayName: "Payshop"),
        Glyph(name: "multibanco", codePoint: 0xF05B, displayName: "Multibanco"),
        Glyph(name: "gratipay-sign", codePoint: 0xF05C, displayName: "Gratipay Sign"),
        Glyph(name: "six", codePoint: 0xF05D, displayName: "Six"),
        Glyph(name: "cashcloud", codePoint: 0xF05E, displayName: "CashCloud"),
        Glyph(name: "interac-alt", codePoint: 0xF05F, displayName: "Interac (Alternate)"),
        Glyph(name: "klarna", codePoint: 0xF060, displayName: "Klarna"),
        Glyph(name: "bitpay", codePoint: 0xF061, displayName: "BitPay"),
        Glyph(name: "venmo", codePoint: 0xF062, displayName: "Venmo"),
        Glyph(name: "visa-debit", codePoint: 0xF063, displayName: "Visa Debit"),
        Glyph(name: "alipay", codePoint: 0xF064, displayName: "Alipay"),
        Glyph(name: "diners-alt", codePoint: 0xF065, displayName: "Diners (Alternate)"),
        Glyph(name: "hipercard", codePoint: 0xF066, displayName: "Hipercard"),
        Glyph(name: "skrill-alt", codePoint: 0xF067, displayName: "Skrill (Alternate)"),
        Glyph(name: "shopify", codePoint: 0xF068, displayName: "Shopify"),
        Glyph(name: "direct-debit", codePoint: 0xF069, displayName: "Direct Debit"),
        Glyph(name: "sodexo", codePoint: 0xF06A, displayName: "Sodexo"),
        Glyph(name: "bpay", codePoint: 0xF06B, displayName: "BPAY"),
        Glyph(name: "contactless", codePoint: 0xF06C, displayName: "Contactless"),
        Glyph(name: "contactless-alt", codePoint: 0xF06D, displayName: "Contactless (Alternate)"),
        Glyph(name: "eth", codePoint: 0xF06E, displayName: "ETH"),
        Glyph(name: "ltc", codePoint: 0xF06F, displayName: "LTC"),
        Glyph(name: "visa-pay", codePoint: 0xF070, displayName: "Visa Pay"),
        Glyph(name: "wechat-pay", codePoint: 0xF071, displayName: "WeChat Pay"),
        Glyph(name: "amazon-pay", codePoint: 0xF072, displayName: "Amazon Pay"),
        Glyph(name: "amazon-pay-alt", codePoint: 0xF073, displayName: "Amazon Pay (Alternate)"),
    ]
}
