import XCTest

/// The over-budget insight card, the analysis and the filtered ledger (v1.2, BI-04). Seeded with
/// `KAKEIBO_SEED_INSIGHT` (see `AppServices.seedInsight`).
final class BudgetInsightUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // The Japanese test plan configuration runs only the smoke test; these tests force English.
        try XCTSkipIf(ProcessInfo.processInfo.environment["KAKEIBO_SMOKE_ONLY"] == "1", "Smoke test only in this configuration")
    }

    @MainActor
    func testOverBudgetCardAnalysisAndFilteredLedger() {
        let app = launch("over")
        let card = scrollToCard(app)
        XCTAssertTrue(card.staticTexts["Why am I over?"].exists)
        app.buttons["insight.see"].tap()

        // Analysis: overspend, drivers with their share, ¥0 for the rest of the month, Review budget.
        XCTAssertTrue(app.buttons["analysis.back"].waitForExistence(timeout: 3))
        XCTAssertTrue(element(app, "analysis.amount").label.contains("7,000 yen"), element(app, "analysis.amount").label)
        let drivers = app.buttons.matching(identifier: "analysis.driver")
        XCTAssertTrue(drivers.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue((1...3).contains(drivers.count), "\(drivers.count) drivers")
        XCTAssertTrue(element(app, "analysis.explained").label.contains("of the ¥7,000 overspend"),
                      element(app, "analysis.explained").label)
        XCTAssertTrue(element(app, "analysis.daily").label.contains("0 yen"), element(app, "analysis.daily").label)
        XCTAssertTrue(element(app, "analysis.weekly").label.contains("0 yen"), element(app, "analysis.weekly").label)
        XCTAssertTrue(scrollTo(app.buttons["analysis.review"], in: app).exists)
        XCTAssertFalse(element(app, "analysis.closed").exists)

        // A driver opens its expenses for the month; Back returns to the analysis.
        scrollTo(drivers.firstMatch, in: app, down: false).tap()
        XCTAssertTrue(app.buttons["filtered.back"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["ledger.row"].firstMatch.exists)
        app.buttons["filtered.back"].tap()
        XCTAssertTrue(app.buttons["analysis.back"].waitForExistence(timeout: 3))
        app.buttons["analysis.back"].tap()
        XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testOnPaceShowsHeadsUpAndRestOfMonthAmounts() {
        let app = launch("onPace")
        let card = scrollToCard(app)
        XCTAssertTrue(card.staticTexts["Heads up"].exists)
        app.buttons["insight.see"].tap()
        XCTAssertTrue(element(app, "analysis.status").waitForExistence(timeout: 3))
        XCTAssertEqual(element(app, "analysis.status").label, "On pace to go over")
        XCTAssertTrue(element(app, "analysis.amount").label.contains("37,000 yen"))
        XCTAssertFalse(element(app, "analysis.daily").label.hasSuffix(" 0 yen"), element(app, "analysis.daily").label)
    }

    @MainActor
    func testClosedMonthIsReadOnly() {
        let app = launch("closed")
        XCTAssertTrue(app.buttons["ledger.previous"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "insight.card").exists, "this month has no budget")
        app.buttons["ledger.previous"].tap()
        scrollToCard(app)
        app.buttons["insight.see"].tap()
        XCTAssertTrue(app.buttons["analysis.back"].waitForExistence(timeout: 3))
        XCTAssertEqual(element(app, "analysis.status").label, "Closed month · Read only")
        XCTAssertTrue(scrollTo(element(app, "analysis.closed"), in: app).exists)
        XCTAssertFalse(app.buttons["analysis.review"].exists)
        XCTAssertFalse(element(app, "analysis.guidance").exists)
    }

    @MainActor
    func testLimitedHistoryExplainsItself() {
        let app = launch("limited")
        let card = scrollToCard(app)
        XCTAssertTrue(card.staticTexts["Comparisons with your usual spending start after your first full month with expenses."].exists)
        app.buttons["insight.see"].tap()
        XCTAssertTrue(element(app, "analysis.limited").waitForExistence(timeout: 3))
        XCTAssertTrue(element(app, "analysis.explained").label.contains("not causes"))
    }

    @MainActor
    func testNoCardWithoutAnInsight() {
        let app = XCUIApplication()
        app.launchEnvironment["KAKEIBO_SEED_SAMPLE"] = "1"
        configure(app)
        app.launch()
        XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "insight.card").exists)
    }

    /// Until BI-05, "Review budget" opens the budget sheet.
    @MainActor
    func testReviewBudgetOpensTheBudgetSheet() {
        let app = launch("over")
        scrollToCard(app)
        app.buttons["insight.see"].tap()
        scrollTo(app.buttons["analysis.review"], in: app).tap()
        XCTAssertTrue(app.textFields["budget.amount"].waitForExistence(timeout: 3))
    }

    /// Saving an expense refreshes the card: on pace becomes over budget.
    @MainActor
    func testCardRefreshesAfterASave() {
        let app = launch("onPace")
        XCTAssertTrue(scrollToCard(app).staticTexts["Heads up"].exists)
        app.swipeDown(); app.swipeDown()
        app.buttons["ledger.add"].tap()
        let amount = app.textFields["review.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("5000")
        app.buttons["review.save"].tap()
        XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToCard(app).staticTexts["Why am I over?"].waitForExistence(timeout: 3))
    }

    /// PR screenshots: each state's card and analysis, light and dark. Opt-in:
    /// `TEST_RUNNER_KAKEIBO_INSIGHT_SHOTS=1 xcodebuild test … -only-testing:KakeiboUITests/BudgetInsightUITests/testScreenshots`
    @MainActor
    func testScreenshots() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KAKEIBO_INSIGHT_SHOTS"] == "1", "Opt-in screenshots")
        for scheme in ["light", "dark"] {
            for state in ["onPace", "over", "closed", "limited"] {
                let app = launch(state, colorScheme: scheme)
                // The budget alert banner (B-07) would cover the top of each shot.
                let dismiss = app.buttons["budget.alert.dismiss"]
                if dismiss.waitForExistence(timeout: 3) { dismiss.tap() }
                if state == "closed" {
                    XCTAssertTrue(app.buttons["ledger.previous"].waitForExistence(timeout: 5))
                    app.buttons["ledger.previous"].tap()
                }
                scrollToCard(app)
                attach(app, "\(state)-\(scheme)-1-card")
                app.buttons["insight.see"].tap()
                XCTAssertTrue(app.buttons["analysis.back"].waitForExistence(timeout: 3))
                attach(app, "\(state)-\(scheme)-2-analysis")
                app.swipeUp()
                attach(app, "\(state)-\(scheme)-3-analysis")
                app.swipeUp()
                attach(app, "\(state)-\(scheme)-4-analysis")
                if state == "over" {
                    app.swipeDown(); app.swipeDown()
                    app.buttons["analysis.driver"].firstMatch.tap()
                    XCTAssertTrue(app.buttons["filtered.back"].waitForExistence(timeout: 3))
                    attach(app, "\(state)-\(scheme)-5-filtered")
                }
                app.terminate()
            }
        }
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ insight: String, colorScheme: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KAKEIBO_SEED_INSIGHT"] = insight
        if let colorScheme { app.launchEnvironment["KAKEIBO_COLOR_SCHEME"] = colorScheme }
        configure(app)
        app.launch()
        return app
    }

    private func configure(_ app: XCUIApplication) {
        app.launchEnvironment["KAKEIBO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KAKEIBO_NO_REFINER"] = "1"
        // No system prompt; the in-app banner still shows.
        app.launchEnvironment["KAKEIBO_NOTIFICATIONS"] = "denied"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_JP"]
    }

    @discardableResult @MainActor
    private func scrollToCard(_ app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 5))
        let card = element(app, "insight.card")
        scrollTo(app.buttons["insight.see"], in: app)
        XCTAssertTrue(card.exists, "insight card")
        return card
    }

    @discardableResult @MainActor
    private func scrollTo(_ target: XCUIElement, in app: XCUIApplication, down: Bool = true) -> XCUIElement {
        var swipes = 0
        while !(target.exists && target.isHittable), swipes < 8 {
            if down { app.swipeUp() } else { app.swipeDown() }
            swipes += 1
        }
        return target
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
