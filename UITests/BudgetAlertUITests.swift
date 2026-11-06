import XCTest

/// The in-app budget alert banner after saves (v1.1, B-07). Alerts start off and iOS
/// permission is not asked, so this also checks the banner shows without notifications.
final class BudgetAlertUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // The Japanese test plan configuration runs only the smoke test; these tests force English.
        try XCTSkipIf(ProcessInfo.processInfo.environment["KAKEIBO_SMOKE_ONLY"] == "1", "Smoke test only in this configuration")
    }

    @MainActor
    func testEightyThenHundredBannersAfterSaving() {
        let app = XCUIApplication()
        app.launchEnvironment["KAKEIBO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KAKEIBO_NO_REFINER"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_JP"]
        app.launch()

        // Budget ¥10,000.
        XCTAssertTrue(app.buttons["budget.cta.button"].waitForExistence(timeout: 5))
        app.buttons["budget.cta.button"].tap()
        let budget = app.textFields["budget.amount"]
        XCTAssertTrue(budget.waitForExistence(timeout: 3))
        budget.tap()
        budget.typeText("10000")
        app.buttons["budget.save"].tap()
        XCTAssertTrue(app.buttons["budget.edit"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "budget.alert.80").exists, "no spend yet")

        // ¥7,999: one yen below 80%, no banner.
        add(app, yen: "7999", store: "Below")
        XCTAssertFalse(element(app, "budget.alert.80").waitForExistence(timeout: 2))

        // ¥1 more: exactly 80%.
        add(app, yen: "1", store: "Eighty")
        let eighty = element(app, "budget.alert.80")
        XCTAssertTrue(eighty.waitForExistence(timeout: 5))
        let text = app.descendants(matching: .any)["budget.alert.text"].firstMatch
        XCTAssertTrue(text.label.contains("80%"), text.label)
        XCTAssertTrue(text.label.contains("2,000"), "what is left: \(text.label)")
        app.buttons["budget.alert.dismiss"].tap()
        XCTAssertTrue(waitForAbsence(eighty))

        // ¥2,500 more: over budget.
        add(app, yen: "2500", store: "Over")
        XCTAssertTrue(element(app, "budget.alert.100").waitForExistence(timeout: 5))
        XCTAssertTrue(text.label.contains("500"), "over by: \(text.label)")
        app.buttons["budget.alert.dismiss"].tap()

        // Nothing rearms: another save raises no banner.
        add(app, yen: "100", store: "After")
        XCTAssertFalse(element(app, "budget.alert.100").waitForExistence(timeout: 2))
        XCTAssertFalse(element(app, "budget.alert.80").exists)
    }

    // MARK: Helpers

    @MainActor
    private func add(_ app: XCUIApplication, yen: String, store name: String) {
        app.buttons["ledger.add"].tap()
        let amount = app.textFields["review.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText(yen)
        let store = app.textFields["review.store"]
        store.tap()
        store.typeText(name)
        app.buttons["review.save"].tap()
        XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor
    private func waitForAbsence(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 3) == .completed
    }
}
