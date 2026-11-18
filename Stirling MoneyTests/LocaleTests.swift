import Foundation
import Testing
@testable import Stirling_Money

/// Typing and showing amounts in other locales (`Decimal(userInput:)`, `.localCurrency`, `editableText`). Most checks
/// are round trips rather than exact strings, since formatting details come from the system's locale data.
struct LocaleTests {
    static let locales = ["en_US", "en_GB", "de_DE", "fr_FR", "de_CH", "ja_JP", "es_MX", "ar_SA"]

    @Test(arguments: locales)
    func amountsShownAsCurrencyParseBack(_ identifier: String) throws {
        let locale = Locale(identifier: identifier)
        // Yen have no minor unit, so use a whole amount there.
        let amounts: [Decimal] = try identifier == "ja_JP"
            ? [1250, -1250, 0, 1_234_567]
            : [#require(Decimal(string: "1250.75")), #require(Decimal(string: "-1250.75")), 0, #require(Decimal(string: "1234567.89"))]
        for amount in amounts {
            let shown = amount.formatted(.localCurrency(in: locale))
            #expect(Decimal(userInput: shown, locale: locale) == amount, "\(identifier): \(shown)")
        }
    }

    @Test(arguments: locales)
    func editableTextParsesBack(_ identifier: String) {
        let locale = Locale(identifier: identifier)
        let amount = identifier == "ja_JP" ? Decimal(1250) : Decimal(string: "1250.75")!
        let text = amount.editableText(in: locale)
        #expect(Decimal(userInput: text, locale: locale) == amount, "\(identifier): \(text)")
    }

    @Test func eachLocaleReadsItsOwnSeparators() throws {
        let germany = Locale(identifier: "de_DE")
        #expect(Decimal(userInput: "1.250,75", locale: germany) == Decimal(string: "1250.75"))
        #expect(Decimal(userInput: "1250,75", locale: germany) == Decimal(string: "1250.75"))
        #expect(Decimal(userInput: "1.250,75 €", locale: germany) == Decimal(string: "1250.75"))
        #expect(Decimal(string: "1250.75")?.editableText(in: germany) == "1250,75")

        let us = Locale(identifier: "en_US")
        #expect(Decimal(userInput: "$1,250.75", locale: us) == Decimal(string: "1250.75"))
        #expect(Decimal(userInput: "1250.75", locale: us) == Decimal(string: "1250.75"))

        let switzerland = Locale(identifier: "de_CH")
        let shown = try #require(Decimal(string: "1250.75")?.formatted(.localCurrency(in: switzerland)))
        #expect(shown.contains("CHF"))
        #expect(Decimal(userInput: shown, locale: switzerland) == Decimal(string: "1250.75"))
    }

    @Test func eachLocaleUsesItsOwnCurrency() throws {
        let amount = try #require(Decimal(string: "10"))
        #expect(amount.formatted(.localCurrency(in: Locale(identifier: "en_US"))).contains("$"))
        #expect(amount.formatted(.localCurrency(in: Locale(identifier: "de_DE"))).contains("€"))
        #expect(amount.formatted(.localCurrency(in: Locale(identifier: "en_GB"))).contains("£"))
        // A locale with no region has no currency: fall back to US dollars.
        #expect(amount.formatted(.localCurrency(in: Locale(identifier: "en"))).contains("$"))
    }

    @Test func positiveAmountsDropTheSignInAnyLocale() {
        let germany = Locale(identifier: "de_DE")
        #expect(Decimal(positiveUserInput: "-12,50", locale: germany) == Decimal(string: "12.5"))
        #expect(Decimal(positiveUserInput: "0,00", locale: germany) == nil)
        #expect(Decimal(positiveUserInput: "zwölf", locale: germany) == nil)
    }

    @Test func csvAmountsUseAPointWhateverTheLocale() throws {
        // `TransactionCSV` writes Decimal's description, which doesn't depend on the locale.
        let amount = try #require(Decimal(userInput: "-1.250,75", locale: Locale(identifier: "de_DE")))
        #expect("\(amount)" == "-1250.75")
    }
}
