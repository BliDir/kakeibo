import XCTest

/// The core flow, end to end: add an expense by hand, save it, find it in the ledger with the
/// right amount, open its details and its edit form, delete it, and see the ledger empty again.
///
/// Runs in both test plan configurations, English and Japanese. The language comes from the
/// configuration (not launch arguments), so this test never forces one. Controls are found by
/// accessibility identifier only; amounts are checked by their digits, which both languages
/// show ("1,234 yen" / "1,234円").
final class SmokeTests: XCTestCase {
    /// Set by the test plan configuration: "en" or "ja".
    private var language: String { ProcessInfo.processInfo.environment["KAKEIBO_TEST_LANGUAGE"] ?? "en" }

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAddFindOpenAndDeleteAnExpense() {
        let app = XCUIApplication()
        app.launchEnvironment["KAKEIBO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KAKEIBO_NO_REFINER"] = "1"
        app.launch()

        // Empty ledger, in the configuration's language.
        let add = app.buttons["ledger.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "ledger.empty").exists, "starts with an empty ledger")
        XCTAssertEqual(app.buttons.matching(identifier: "ledger.row").count, 0)
        // The month header: "2026年11月 令和8年11月" in Japanese, "November 2026 令和8年11月 · Reiwa 8" in English.
        let month = app.staticTexts["ledger.month"].firstMatch.label
        if language == "ja" {
            XCTAssertFalse(month.contains("Reiwa"), "Japanese month header expected, got \(month)")
        } else {
            XCTAssertTrue(month.contains("Reiwa"), "English month header expected, got \(month)")
        }

        // Add an expense by hand and save it.
        add.tap()
        let amount = app.textFields["review.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["review.save"].isEnabled, "nothing to save without an amount")
        amount.tap()
        amount.typeText("1234")
        let store = app.textFields["review.store"]
        store.tap()
        store.typeText("Smoke Test Cafe")
        let save = app.buttons["review.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // It is in the ledger with the right amount.
        XCTAssertTrue(element(app, "banner").waitForExistence(timeout: 5), "save confirmation")
        let row = app.buttons["ledger.row"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "ledger.row").count, 1)
        XCTAssertTrue(row.label.contains("Smoke Test Cafe"), row.label)
        XCTAssertTrue(row.label.contains("1,234"), row.label)
        XCTAssertTrue(app.staticTexts["ledger.total"].label.contains("1,234"), app.staticTexts["ledger.total"].label)
        XCTAssertFalse(element(app, "ledger.empty").exists)

        // Open it: the details show the saved values, and so does the edit form.
        row.tap()
        let detailAmount = element(app, "detail.amount")
        XCTAssertTrue(detailAmount.waitForExistence(timeout: 5))
        XCTAssertTrue(detailAmount.label.contains("1,234"), detailAmount.label)
        XCTAssertTrue(element(app, "detail.store").label.contains("Smoke Test Cafe"))
        app.buttons["detail.edit"].tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "1234")
        XCTAssertEqual(store.value as? String, "Smoke Test Cafe")
        app.buttons["review.cancel"].tap()   // nothing changed, so no question

        // Delete it from the details, with the in-app confirmation.
        let delete = app.buttons["detail.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        var swipes = 0
        while !delete.isHittable, swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        delete.tap()
        let confirm = app.buttons["confirm.action"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        // The ledger is empty again.
        XCTAssertTrue(element(app, "ledger.empty").waitForExistence(timeout: 5), "ledger empty after delete")
        XCTAssertEqual(app.buttons.matching(identifier: "ledger.row").count, 0)
        XCTAssertTrue(app.staticTexts["ledger.total"].label.hasPrefix("0"), app.staticTexts["ledger.total"].label)
    }

    /// An element by identifier, whatever its type (some are combined containers).
    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }
}
