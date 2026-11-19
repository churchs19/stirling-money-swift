import Foundation
import Testing
@testable import StirlingMoney_Watch_App

@MainActor
struct WatchStoreTests {
    /// A summary file in a fresh temporary folder, so tests don't touch the App Group.
    private func temporaryFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: WidgetSnapshot.fileName)
    }

    private func summary(updatedAt: Date, accountName: String = "Checking") throws -> Data {
        let snapshot = WidgetSnapshot(
            accounts: [.init(id: "a", name: accountName, balance: 100, postedBalance: 100)],
            goals: [],
            updatedAt: updatedAt
        )
        return try JSONEncoder().encode(snapshot)
    }

    @Test func startsEmptyWithoutASavedSummary() throws {
        let store = try WatchStore(fileURL: temporaryFile())
        #expect(store.snapshot == nil)
    }

    @Test func keepsAndSavesANewSummary() throws {
        let file = try temporaryFile()
        let store = WatchStore(fileURL: file)

        #expect(try store.receive(summary(updatedAt: Date(timeIntervalSince1970: 1000))))
        #expect(store.snapshot?.accounts.first?.name == "Checking")

        // A new launch loads what was saved.
        let relaunched = WatchStore(fileURL: file)
        #expect(relaunched.snapshot == store.snapshot)
    }

    @Test func ignoresAnOlderSummary() throws {
        let store = try WatchStore(fileURL: temporaryFile())
        try store.receive(summary(updatedAt: Date(timeIntervalSince1970: 2000), accountName: "New"))

        // A reply and an application context can arrive out of order.
        #expect(try !store.receive(summary(updatedAt: Date(timeIntervalSince1970: 1000), accountName: "Old")))
        #expect(store.snapshot?.accounts.first?.name == "New")
    }

    @Test func anUnchangedSummaryStillCountsAsHearingFromThePhone() throws {
        let store = try WatchStore(fileURL: temporaryFile())
        let data = try summary(updatedAt: Date(timeIntervalSince1970: 1000))
        store.receive(data, now: Date(timeIntervalSince1970: 1000))
        #expect(store.asOf == Date(timeIntervalSince1970: 1000))

        // The iPhone answers a refresh with the same summary: the figures are confirmed as of now.
        store.receive(data, now: Date(timeIntervalSince1970: 5000))
        #expect(store.asOf == Date(timeIntervalSince1970: 5000))
    }

    @Test func complicationChoicesChangeWithAccountsGoalsAndBudgetsOnly() {
        let sample = WidgetSnapshot.sample
        // The first summary: the watch face editor's list needs rebuilding.
        #expect(WatchStore.complicationChoicesChanged(from: nil, to: sample))

        // New balances alone don't change the list.
        var newBalances = sample
        newBalances.accounts[0].balance += 10
        newBalances.goals[0].currentAmount += 10
        #expect(!WatchStore.complicationChoicesChanged(from: sample, to: newBalances))

        var renamed = sample
        renamed.accounts[0].name = "Everyday"
        #expect(WatchStore.complicationChoicesChanged(from: sample, to: renamed))

        var goalRemoved = sample
        goalRemoved.goals.removeLast()
        #expect(WatchStore.complicationChoicesChanged(from: sample, to: goalRemoved))

        var budgetSpending = sample
        budgetSpending.budgets[0].spent += 10
        #expect(!WatchStore.complicationChoicesChanged(from: sample, to: budgetSpending))

        var budgetRenamed = sample
        budgetRenamed.budgets[0].name = "Groceries"
        #expect(WatchStore.complicationChoicesChanged(from: sample, to: budgetRenamed))
    }

    @Test func ignoresDataThatIsNotASummary() throws {
        let store = try WatchStore(fileURL: temporaryFile())
        #expect(!store.receive(Data("not json".utf8)))
        #expect(store.snapshot == nil)
    }

    @Test func readsASummaryFromBeforeBudgetsWereAdded() throws {
        let json = #"{"accounts":[{"id":"a","name":"Checking","balance":10,"postedBalance":10}],"goals":[],"updatedAt":0}"#
        let store = try WatchStore(fileURL: temporaryFile())
        #expect(store.receive(Data(json.utf8)))
        #expect(store.snapshot?.budgets.isEmpty == true)
    }

    @Test func budgetFromAnEndedPeriodIsNotCurrent() {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(86400 * 30)
        let budget = WidgetSnapshot.BudgetSummary(
            id: "b", name: "Food", amount: 400, spent: 100, periodStart: start, periodEnd: end
        )
        #expect(budget.isCurrent(on: end.addingTimeInterval(-1)))
        #expect(!budget.isCurrent(on: end), "the Watch should ask the iPhone for the new period")
    }

    @Test func pagesShowRecurringTransactionsFromTheDayTheyFallDue() throws {
        var summary = WidgetSnapshot.sample
        summary.upcoming = [
            .init(date: Calendar.current.startOfDay(for: .now.addingTimeInterval(2 * 86400)), accountID: "checking", amount: -50),
        ]
        let store = WatchStore(fileURL: nil, snapshot: summary)
        store.showToday(.now)
        #expect(store.current?.accounts.first?.balance == 1250.75, "not due yet")

        store.showToday(.now.addingTimeInterval(3 * 86400))
        #expect(store.current?.accounts.first?.balance == 1200.75)
        #expect(store.snapshot?.accounts.first?.balance == 1250.75, "the saved summary itself doesn't change")
    }
}
