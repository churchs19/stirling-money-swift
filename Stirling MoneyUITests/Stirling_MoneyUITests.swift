import XCTest

/// End-to-end checks on the iPhone simulator. Each test launches the app with `-UITesting`: the sample data in memory
/// (Checking $10,229.11, Credit Card -$1,068.38, Savings $10,500.00; total $19,660.73), fresh settings, and no widget
/// summary or Watch. US English, so amounts read the same whatever the simulator's language.
@MainActor
final class Stirling_MoneyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    // MARK: Helpers

    /// Any element with this accessibility identifier.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Fails unless `element` appears within a few seconds.
    @discardableResult
    private func waitFor(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element) didn't appear", file: file, line: line)
        return element
    }

    /// Waits for the element with `identifier` to have `text` in its label. SwiftUI folds an amount into the label
    /// of its row or tile ("Total, $19,660.73"), so amounts are checked there.
    private func expectLabel(of identifier: String, toContain text: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        let found = expectation(for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: target)
        if XCTWaiter().wait(for: [found], timeout: 5) != .completed {
            XCTFail("\(identifier) is \"\(target.exists ? target.label : "missing")\", not containing \(text)", file: file, line: line)
        }
    }

    private func tab(_ name: String) {
        waitFor(app.tabBars.buttons[name].firstMatch).tap()
    }

    private func type(_ text: String, into identifier: String) {
        let field = waitFor(element(identifier))
        field.tap()
        field.typeText(text)
    }

    private func openAccount(_ name: String) {
        waitFor(element("account.\(name)")).tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
    }

    /// Adds a transaction to the open account's register: type, amount, then payee or the other account.
    private func addTransaction(kind: String = "Withdrawal", amount: String, payee: String? = nil, otherAccount: String? = nil) {
        waitFor(element("addTransaction")).tap()
        if kind != "Withdrawal" {
            waitFor(app.segmentedControls["transactionType"].buttons[kind]).tap()
        }
        type(amount, into: "amount")
        if let payee {
            type(payee, into: "payee")
        }
        if let otherAccount {
            waitFor(element("otherAccount")).tap()
            waitFor(app.buttons[otherAccount].firstMatch).tap()
        }
        waitFor(element("save")).tap()
    }

    private func back() {
        app.navigationBars.buttons.firstMatch.tap()
    }

    // MARK: Accounts

    func testLaunchShowsTheSampleAccountsAndTotal() {
        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: 5))
        expectLabel(of: "accountsTotal", toContain: "$19,660.73")
        expectLabel(of: "account.Checking", toContain: "$10,229.11")
        expectLabel(of: "account.Credit Card", toContain: "-$1,068.38")
        expectLabel(of: "account.Savings", toContain: "$10,500.00")
    }

    func testAddingAnAccountAddsItsBalanceToTheTotal() {
        waitFor(element("addAccount")).tap()
        type("Holiday Fund", into: "accountName")
        type("100", into: "initialBalance")
        waitFor(element("save")).tap()

        expectLabel(of: "account.Holiday Fund", toContain: "$100.00")
        expectLabel(of: "accountsTotal", toContain: "$19,760.73")
    }

    // MARK: Register

    func testWithdrawalLowersTheBalanceAndTheTotal() {
        openAccount("Checking")
        addTransaction(amount: "25", payee: "Hardware Store")

        waitFor(element("transaction.Hardware Store"))
        expectLabel(of: "availableBalance", toContain: "$10,204.11")
        back()
        expectLabel(of: "accountsTotal", toContain: "$19,635.73")
    }

    func testTransferMovesMoneyWithoutChangingTheTotal() {
        openAccount("Checking")
        addTransaction(kind: "Transfer", amount: "100", otherAccount: "Savings")

        expectLabel(of: "availableBalance", toContain: "$10,129.11")
        back()
        expectLabel(of: "account.Savings", toContain: "$10,600.00")
        expectLabel(of: "accountsTotal", toContain: "$19,660.73")
    }

    func testSearchFindsTransactionsByPayee() {
        openAccount("Checking")
        // The search field is tucked under the title until the list is pulled down.
        waitFor(element("availableBalance")).swipeDown()
        let search = waitFor(app.searchFields.firstMatch)
        search.tap()
        search.typeText("Coffee")

        waitFor(element("transaction.Coffee Cart"))
        XCTAssertFalse(element("transaction.Landlord").exists)
    }

    func testMarkingATransactionPostedChangesThePostedBalance() {
        openAccount("Checking")
        // Posted leaves out the unposted $500 transfer and Coffee Cart ($4.50).
        expectLabel(of: "postedBalance", toContain: "$10,733.61")
        // The row's checkmark.
        let checkmark = waitFor(app.buttons["transaction.Coffee Cart"].firstMatch)
        XCTAssertEqual(checkmark.label, "Not posted")
        checkmark.tap()

        expectLabel(of: "postedBalance", toContain: "$10,729.11")
        XCTAssertEqual(app.buttons["transaction.Coffee Cart"].firstMatch.label, "Posted")
    }

    // MARK: Budgets and goals

    func testAddingABudgetShowsItsCard() {
        tab("Budgets")
        waitFor(element("addBudget")).tap()
        type("Travel", into: "budgetName")
        type("200", into: "budgetAmount")
        waitFor(element("save")).tap()

        waitFor(element("budget.Travel"))
    }

    func testAddingAGoalShowsItsCard() {
        tab("Goals")
        waitFor(element("addGoal")).tap()
        type("Bike", into: "goalName")
        type("800", into: "goalTarget")
        waitFor(element("goalAccount")).tap()
        waitFor(app.buttons["Savings"].firstMatch).tap()
        waitFor(element("save")).tap()

        waitFor(element("goal.Bike"))
    }

    // MARK: Reports and settings

    func testEveryReportOpens() {
        tab("Reports")
        for (identifier, title) in [
            ("report.netIncome", "Net Income"),
            ("report.categorySpending", "Spending by Category"),
            ("report.categoryTrend", "Category Over Time"),
            ("report.budgetHistory", "Budget History"),
        ] {
            waitFor(element(identifier)).tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), title)
            back()
        }
    }

    func testLayoutSwitchesBetweenTilesAndList() {
        let toggle = waitFor(element("toggleLayout"))
        XCTAssertEqual(toggle.label, "Show as List", "fresh settings start with tiles")
        toggle.tap()
        XCTAssertEqual(element("toggleLayout").label, "Show as Tiles")
        expectLabel(of: "account.Checking", toContain: "$10,229.11")
        expectLabel(of: "accountsTotal", toContain: "$19,660.73")

        element("toggleLayout").tap()
        XCTAssertEqual(element("toggleLayout").label, "Show as List")
    }

    func testChoosingACustomAccentShowsTheColorPicker() {
        waitFor(app.navigationBars["Accounts"].buttons["More"]).tap()
        waitFor(element("settings")).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("customAccent").exists, "fresh settings use the default accent")

        waitFor(element("accentChoice")).tap()
        waitFor(app.buttons["Custom"].firstMatch).tap()
        waitFor(element("customAccent"))
    }

    // MARK: Performance

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            // With the same launch arguments, so it never opens the real store or writes the widget summary.
            let launched = XCUIApplication()
            launched.launchArguments = app.launchArguments
            launched.launch()
        }
    }
}
