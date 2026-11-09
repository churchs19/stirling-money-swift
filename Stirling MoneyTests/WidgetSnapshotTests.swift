import Foundation
import SwiftData
import Testing
@testable import Stirling_Money

@MainActor
struct WidgetSnapshotTests {
    @Test func snapshotSummarizesAccountsAndGoals() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let savings = Account(name: "Savings", initialBalance: 1000)
        let checking = Account(name: "Checking", initialBalance: 200)
        context.insert(savings)
        context.insert(checking)
        Ledger.addTransaction(.deposit, amount: 500, to: savings, payee: "Paycheck", isPosted: true, in: context)
        Ledger.addTransaction(.withdrawal, amount: 50, to: checking, payee: "Shop", in: context)
        let goal = Goal(name: "Trip", targetAmount: 2000, targetDate: day(2027, 6, 1), initialBalance: 1000)
        context.insert(goal)
        goal.account = savings
        try context.save()

        let snapshot = WidgetSnapshot(accounts: [savings, checking], goals: [goal], now: day(2026, 11, 6))

        #expect(snapshot.accounts.map(\.name) == ["Checking", "Savings"], "sorted by name")
        #expect(snapshot.accounts[0].balance == 150)
        #expect(snapshot.accounts[0].postedBalance == 200)
        #expect(snapshot.accounts[1].balance == 1500)
        #expect(snapshot.goals == [
            WidgetSnapshot.GoalSummary(
                id: WidgetSnapshot.widgetID(for: goal), name: "Trip", accountName: "Savings",
                currentAmount: 1500, targetAmount: 2000, progress: 0.5, targetDate: day(2027, 6, 1)
            ),
        ])
    }

    @Test func snapshotCarriesAccountIcons() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let card = Account(name: "Card", iconName: "pf-visa")
        let bank = Account(name: "Bank", iconName: "building.columns")
        let plain = Account(name: "Plain")
        [card, bank, plain].forEach { context.insert($0) }
        try context.save()

        let accounts = WidgetSnapshot(accounts: [card, bank, plain], goals: []).accounts
        let byName = Dictionary(uniqueKeysWithValues: accounts.map { ($0.name, $0) })
        // The widget gets a glyph's character, since it doesn't have PaymentFont's name table.
        #expect(byName["Card"]?.iconGlyph == PaymentFont.glyph(forIconName: "pf-visa")?.character)
        #expect(byName["Card"]?.iconSymbol == nil)
        #expect(byName["Bank"]?.iconSymbol == "building.columns")
        #expect(byName["Bank"]?.iconGlyph == nil)
        #expect(byName["Plain"]?.iconSymbol == nil && byName["Plain"]?.iconGlyph == nil)
    }

    @Test func snapshotFromBeforeIconsStillDecodes() throws {
        let json = #"{"accounts":[{"id":"a","name":"Checking","balance":10,"postedBalance":10}],"goals":[],"updatedAt":0}"#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.accounts.first?.iconSymbol == nil)
    }

    @Test func idsAreStableAndDistinct() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let first = Account(name: "A")
        let second = Account(name: "B")
        context.insert(first)
        context.insert(second)
        try context.save()

        let id = WidgetSnapshot.widgetID(for: first)
        #expect(!id.isEmpty)
        first.name = "Renamed"
        #expect(WidgetSnapshot.widgetID(for: first) == id, "renaming keeps the widget pointed at the account")
        #expect(WidgetSnapshot.widgetID(for: second) != id)
    }

    @Test func snapshotSurvivesJSONRoundTrip() throws {
        let snapshot = try WidgetSnapshot(
            accounts: [.init(id: "a", name: "Checking", balance: #require(Decimal(string: "1250.75")), postedBalance: 1000)],
            goals: [],
            updatedAt: day(2026, 11, 6)
        )
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }
}

struct DeepLinkTests {
    @Test func accountLinkRoundTripsAnIDWithURLSpecialCharacters() throws {
        // Widget IDs are base64, which can contain +, / and =.
        let link = DeepLink.account(id: "eyJh+b/c==")
        #expect(link.url.scheme == "stirlingmoney")
        #expect(DeepLink(url: link.url) == link)
    }

    @Test func goalsLinkRoundTrips() throws {
        #expect(DeepLink.goals.url.absoluteString == "stirlingmoney://goals")
        #expect(DeepLink(url: DeepLink.goals.url) == .goals)
    }

    @Test func otherURLsAreIgnored() throws {
        #expect(try DeepLink(url: #require(URL(string: "https://example.com/account?id=1"))) == nil)
        #expect(try DeepLink(url: #require(URL(string: "stirlingmoney://budget?id=1"))) == nil)
        #expect(try DeepLink(url: #require(URL(string: "stirlingmoney://account"))) == nil)
    }
}
