import XCTest

/// A smoke test of the Watch app's three pages, with `WidgetSnapshot.sample` (`-UseSampleData`): Checking $1,250.75
/// and Savings $8,500.00 (total $9,750.75), the Food and Fun budgets, and the Emergency Fund goal. It doesn't need a
/// paired iPhone.
@MainActor
final class StirlingMoney_Watch_AppUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UseSampleData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    /// Waits for any element whose label contains `text`. watchOS often folds a row's texts into one label.
    private func expectText(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let match = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 5), "nothing shows \"\(text)\"", file: file, line: line)
    }

    /// Swipes up until a page titled `title` shows. A page's list scrolls to its end before the next page comes in.
    private func swipeUp(toPage title: String, file: StaticString = #filePath, line: UInt = #line) {
        let heading = app.staticTexts[title].firstMatch
        for _ in 0 ..< 5 where !heading.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(heading.waitForExistence(timeout: 5) && heading.isHittable, "didn't reach \(title)", file: file, line: line)
    }

    func testAccountsBudgetsAndGoalsPagesShowTheSummary() {
        expectText("Accounts")
        expectText("$9,750.75")
        expectText("Checking")
        expectText("$1,250.75")
        expectText("Savings")

        // The pages are stacked vertically.
        swipeUp(toPage: "Budgets")
        expectText("Food")
        expectText("$125.00 left")
        expectText("$30.00 over")

        swipeUp(toPage: "Goals")
        expectText("Emergency Fund")
        expectText("$6,500.00 to go")
    }

    func testTappingAnAccountShowsItsPostedBalance() {
        let checking = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Checking")).firstMatch
        XCTAssertTrue(checking.waitForExistence(timeout: 5))
        checking.tap()
        expectText("Posted $1,180.25")
    }

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let launched = XCUIApplication()
            launched.launchArguments = app.launchArguments
            launched.launch()
        }
    }
}
