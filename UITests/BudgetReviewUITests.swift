import XCTest

/// The budget review sheet (v1.2, BI-05), opened from the analysis' "Review budget". Seeded with
/// `KAKEIBO_SEED_INSIGHT` (see `AppServices.seedInsight`): `raise`, `lower` and `steady` give
/// those recommendations, `over` keeps for a one-off, `limited` has no suggestion and `closed`
/// reviews last month.
final class BudgetReviewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // The Japanese test plan configuration runs only the smoke test; these tests force English.
        try XCTSkipIf(ProcessInfo.processInfo.environment["KAKEIBO_SMOKE_ONLY"] == "1", "Smoke test only in this configuration")
    }

    @MainActor
    func testRaiseStartsOnThisMonthAndSavesFromThisMonthOn() {
        let app = openReview("raise")
        XCTAssertEqual(element(app, "budgetReview.recommendation").label, "Suggested: raise budget")
        XCTAssertTrue(element(app, "budgetReview.reason").label.hasPrefix("Dining out"), element(app, "budgetReview.reason").label)
        XCTAssertTrue(element(app, "budgetReview.currentAmount").label.contains("30,000 yen"))
        let suggested = element(app, "budgetReview.suggestedAmount")
        XCTAssertTrue(suggested.exists)
        let field = app.textFields["budgetReview.amount"]
        XCTAssertTrue(field.isEnabled)
        let amount = field.value as? String ?? ""
        XCTAssertTrue(suggested.label.contains(grouped(amount)), "\(suggested.label) / \(amount)")
        XCTAssertTrue(app.buttons["budgetReview.choice.month"].isSelected)

        // Each choice previews before anything is saved; keep locks the amount.
        let preview = element(app, "budgetReview.preview.remaining")
        XCTAssertTrue(scrollTo(preview, in: app).exists)
        XCTAssertTrue(preview.label.hasPrefix("Remaining"), preview.label)
        app.buttons["budgetReview.choice.keep"].tap()
        XCTAssertTrue(preview.label.hasPrefix("Still over by"), preview.label)
        XCTAssertTrue(element(app, "budgetReview.preview.daily").label.hasSuffix(" 0 yen"))
        XCTAssertFalse(field.isEnabled)
        XCTAssertEqual(app.buttons["budgetReview.confirm"].label, "Keep current budget")

        app.buttons["budgetReview.choice.future"].tap()
        XCTAssertTrue(app.buttons["budgetReview.choice.future"].isSelected)
        XCTAssertEqual(app.buttons["budgetReview.confirm"].label, "Confirm new budget")
        app.buttons["budgetReview.confirm"].tap()

        // Saved: the sheet closes and the ledger's budget card shows the new budget.
        XCTAssertTrue(app.buttons["analysis.back"].waitForExistence(timeout: 3))
        XCTAssertFalse(element(app, "budgetReview.sheet").exists)
        app.buttons["analysis.back"].tap()
        XCTAssertTrue(waitForSuffix(element(app, "budget.value"), "\(grouped(amount)) yen"),
                      element(app, "budget.value").label)
    }

    @MainActor
    func testLowerRecommendation() {
        let app = openReview("lower")
        XCTAssertEqual(element(app, "budgetReview.recommendation").label, "Suggested: lower budget")
        XCTAssertTrue(element(app, "budgetReview.reason").label.contains("less than 70%"))
        XCTAssertTrue(app.buttons["budgetReview.choice.month"].isSelected)
    }

    @MainActor
    func testKeepWhenNothingCallsForAChange() {
        let app = openReview("steady")
        XCTAssertEqual(element(app, "budgetReview.recommendation").label, "Suggested: keep budget")
        XCTAssertTrue(element(app, "budgetReview.reason").label.contains("for reference"))
        XCTAssertTrue(app.buttons["budgetReview.choice.keep"].isSelected)
        XCTAssertFalse(app.textFields["budgetReview.amount"].isEnabled)
        // Keep closes without saving.
        app.buttons["budgetReview.confirm"].tap()
        XCTAssertTrue(app.buttons["analysis.back"].waitForExistence(timeout: 3))
        app.buttons["analysis.back"].tap()
        XCTAssertTrue(waitForSuffix(element(app, "budget.value"), "60,000 yen"))
    }

    @MainActor
    func testKeepWhenAOneOffExplainsTheOverspend() {
        let app = openReview("over")
        XCTAssertEqual(element(app, "budgetReview.recommendation").label, "Suggested: keep budget")
        XCTAssertTrue(element(app, "budgetReview.reason").label.contains("one-off"))
        XCTAssertTrue(app.buttons["budgetReview.choice.keep"].isSelected)
    }

    @MainActor
    func testNotEnoughHistoryIsAManualEdit() {
        let app = openReview("limited")
        XCTAssertEqual(element(app, "budgetReview.recommendation").label, "No suggestion yet")
        XCTAssertFalse(element(app, "budgetReview.suggestedAmount").exists)
        let field = app.textFields["budgetReview.amount"]
        XCTAssertEqual(field.value as? String, "30000")
        app.buttons["budgetReview.choice.month"].tap()
        type("45000", into: field, clearing: true)
        app.buttons["budgetReview.confirm"].tap()
        XCTAssertTrue(app.buttons["analysis.back"].waitForExistence(timeout: 3))
        app.buttons["analysis.back"].tap()
        XCTAssertTrue(waitForSuffix(element(app, "budget.value"), "45,000 yen"))
    }

    @MainActor
    func testClosedMonthOpensReadOnly() {
        let app = XCUIApplication()
        configure(app, "closed")
        app.launch()
        XCTAssertTrue(app.buttons["ledger.previous"].waitForExistence(timeout: 5))
        app.buttons["ledger.previous"].tap()
        scrollTo(app.buttons["insight.see"], in: app).tap()
        XCTAssertTrue(app.buttons["analysis.back"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["analysis.review"].exists)
        scrollTo(app.buttons["analysis.reviewClosed"], in: app).tap()

        XCTAssertTrue(element(app, "budgetReview.sheet").waitForExistence(timeout: 3))
        XCTAssertTrue(element(app, "budgetReview.closed").exists)
        XCTAssertFalse(app.textFields["budgetReview.amount"].exists)
        XCTAssertFalse(app.buttons["budgetReview.choice.month"].exists)
        XCTAssertFalse(app.buttons["budgetReview.confirm"].exists)
        XCTAssertEqual(app.buttons["budgetReview.cancel"].label, "Close")
        app.buttons["budgetReview.cancel"].tap()
        XCTAssertTrue(app.buttons["analysis.back"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testInvalidAmountDisablesConfirm() {
        let app = openReview("raise")
        let field = app.textFields["budgetReview.amount"]
        type("0", into: field, clearing: true)
        XCTAssertTrue(element(app, "budgetReview.problem").waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["budgetReview.confirm"].isEnabled)
        XCTAssertTrue(scrollTo(element(app, "budgetReview.preview.invalid"), in: app).exists)
    }

    @MainActor
    func testCancelSavesNothing() {
        let app = openReview("raise")
        type("99000", into: app.textFields["budgetReview.amount"], clearing: true)
        app.buttons["budgetReview.cancel"].tap()
        XCTAssertTrue(app.buttons["analysis.back"].waitForExistence(timeout: 3))
        app.buttons["analysis.back"].tap()
        XCTAssertTrue(waitForSuffix(element(app, "budget.value"), "30,000 yen"))
    }

    @MainActor
    func testFailedSaveKeepsTheInputAndRetries() {
        let app = openReview("raise", failBudgetSaves: 1)
        let field = app.textFields["budgetReview.amount"]
        type("47000", into: field, clearing: true)
        app.buttons["budgetReview.confirm"].tap()
        XCTAssertTrue(element(app, "budgetReview.failed").waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "47000")
        app.buttons["budgetReview.confirm"].tap()
        XCTAssertTrue(app.buttons["analysis.back"].waitForExistence(timeout: 3))
        XCTAssertFalse(element(app, "budgetReview.sheet").exists)
        app.buttons["analysis.back"].tap()
        XCTAssertTrue(waitForSuffix(element(app, "budget.value"), "47,000 yen"))
    }

    /// PR screenshots: each recommendation, limited history and a closed month, light and dark.
    /// Opt-in: `TEST_RUNNER_KAKEIBO_INSIGHT_SHOTS=1 xcodebuild test … -only-testing:KakeiboUITests/BudgetReviewUITests/testScreenshots`
    @MainActor
    func testScreenshots() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KAKEIBO_INSIGHT_SHOTS"] == "1", "Opt-in screenshots")
        for scheme in ["light", "dark"] {
            for state in ["raise", "lower", "steady", "over", "limited", "closed"] {
                let app = XCUIApplication()
                configure(app, state)
                app.launchEnvironment["KAKEIBO_COLOR_SCHEME"] = scheme
                app.launch()
                XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 5))
                let dismiss = app.buttons["budget.alert.dismiss"]
                if dismiss.waitForExistence(timeout: 3) { dismiss.tap() }
                if state == "closed" { app.buttons["ledger.previous"].tap() }
                scrollTo(app.buttons["insight.see"], in: app).tap()
                XCTAssertTrue(app.buttons["analysis.back"].waitForExistence(timeout: 3))
                scrollTo(app.buttons[state == "closed" ? "analysis.reviewClosed" : "analysis.review"], in: app).tap()
                XCTAssertTrue(element(app, "budgetReview.sheet").waitForExistence(timeout: 3))
                attach(app, "\(state)-\(scheme)-1-review")
                if state != "closed" {
                    app.swipeUp()
                    attach(app, "\(state)-\(scheme)-2-review")
                }
                app.terminate()
            }
        }
    }

    // MARK: Helpers

    @MainActor
    private func openReview(_ insight: String, failBudgetSaves: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        configure(app, insight)
        if let failBudgetSaves { app.launchEnvironment["KAKEIBO_FAIL_BUDGET_SAVES"] = String(failBudgetSaves) }
        app.launch()
        XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["insight.see"], in: app).tap()
        XCTAssertTrue(app.buttons["analysis.back"].waitForExistence(timeout: 3))
        scrollTo(app.buttons["analysis.review"], in: app).tap()
        XCTAssertTrue(element(app, "budgetReview.sheet").waitForExistence(timeout: 3))
        return app
    }

    private func configure(_ app: XCUIApplication, _ insight: String) {
        app.launchEnvironment["KAKEIBO_SEED_INSIGHT"] = insight
        app.launchEnvironment["KAKEIBO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KAKEIBO_NO_REFINER"] = "1"
        app.launchEnvironment["KAKEIBO_NOTIFICATIONS"] = "denied"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_JP"]
    }

    /// "46000" → "46,000".
    private func grouped(_ digits: String) -> String {
        guard let value = Int(digits) else { return digits }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: value)) ?? digits
    }

    @MainActor
    private func type(_ text: String, into field: XCUIElement, clearing: Bool = false) {
        field.tap()
        if clearing, let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    @discardableResult @MainActor
    private func scrollTo(_ target: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        var swipes = 0
        while !(target.exists && target.isHittable), swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        return target
    }

    @MainActor
    private func waitForSuffix(_ element: XCUIElement, _ suffix: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label ENDSWITH %@", suffix)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
