import XCTest

/// Setting, editing and removing the month's budget (v1.1, B-04).
final class BudgetUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // The Japanese test plan configuration runs only the smoke test; these tests force English.
        try XCTSkipIf(ProcessInfo.processInfo.environment["KAKEIBO_SMOKE_ONLY"] == "1", "Smoke test only in this configuration")
    }

    @MainActor
    func testSetEditRemoveAndReAdd() {
        let app = launch()
        // No budget: the setup prompt.
        XCTAssertTrue(element(app, "budget.cta").waitForExistence(timeout: 5))
        app.buttons["budget.cta.button"].tap()

        // Set ¥200,000.
        let amount = app.textFields["budget.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["budget.save"].isEnabled, "nothing to save yet")
        XCTAssertFalse(app.buttons["budget.remove"].exists, "no budget to remove yet")
        type("200000", into: amount)
        app.buttons["budget.save"].tap()
        XCTAssertTrue(budgetValue(app).waitForExistence(timeout: 5))
        XCTAssertTrue(budgetValue(app).label.hasSuffix("200,000 yen"), budgetValue(app).label)
        XCTAssertFalse(element(app, "budget.cta").exists)

        // Edit to ¥150,000.
        app.buttons["budget.edit"].tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        XCTAssertEqual(amount.value as? String, "200000")
        type("150000", into: amount, clearing: true)
        app.buttons["budget.save"].tap()
        XCTAssertTrue(waitForLabel(budgetValue(app), "150,000 yen"))

        // Remove, with the in-app confirmation; Keep first, then Remove.
        app.buttons["budget.edit"].tap()
        app.buttons["budget.remove"].tap()
        XCTAssertTrue(app.buttons["confirm.cancel"].waitForExistence(timeout: 3))
        app.buttons["confirm.cancel"].tap()
        XCTAssertTrue(amount.exists, "Keep stays on the sheet")
        app.buttons["budget.remove"].tap()
        app.buttons["confirm.action"].tap()
        XCTAssertTrue(element(app, "budget.cta").waitForExistence(timeout: 5), "back to the setup prompt")

        // Re-add.
        app.buttons["budget.cta.button"].tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        type("120000", into: amount)
        app.buttons["budget.save"].tap()
        XCTAssertTrue(waitForLabel(budgetValue(app), "120,000 yen"))
    }

    @MainActor
    func testInvalidAmountsCannotBeSaved() {
        let app = launch()
        XCTAssertTrue(app.buttons["budget.cta.button"].waitForExistence(timeout: 5))
        app.buttons["budget.cta.button"].tap()
        let amount = app.textFields["budget.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        type("0", into: amount)
        XCTAssertTrue(element(app, "budget.problem").waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["budget.save"].isEnabled)
        type("1000000000", into: amount, clearing: true)   // one yen over the limit
        XCTAssertTrue(element(app, "budget.problem").exists)
        XCTAssertFalse(app.buttons["budget.save"].isEnabled)
        // Cancel stores nothing.
        app.buttons["budget.cancel"].tap()
        XCTAssertTrue(element(app, "budget.cta").waitForExistence(timeout: 3))
    }

    @MainActor
    func testFutureMonthToggleOnAndOff() {
        let app = launch()
        XCTAssertTrue(app.buttons["budget.cta.button"].waitForExistence(timeout: 5))
        app.buttons["budget.cta.button"].tap()
        let amount = app.textFields["budget.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        let toggle = app.switches["budget.template"]
        XCTAssertEqual(toggle.value as? String, "0", "defaults off")
        let explanation = element(app, "budget.template.explanation")
        XCTAssertTrue(explanation.label.hasPrefix("Off:"), explanation.label)

        type("100000", into: amount)
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(explanation.label.hasPrefix("On:") && explanation.label.contains("¥100,000"), explanation.label)
        app.buttons["budget.save"].tap()

        // Reopened: still on. Turn it off.
        XCTAssertTrue(app.buttons["budget.edit"].waitForExistence(timeout: 5))
        app.buttons["budget.edit"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["budget.save"].tap()

        XCTAssertTrue(app.buttons["budget.edit"].waitForExistence(timeout: 5))
        app.buttons["budget.edit"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "0", "stays off")
        XCTAssertTrue(budgetValueExistsBehindSheet(app))
    }

    @MainActor
    func testPastMonthBudgetIsReadOnly() {
        let app = launch(seed: true)   // sample data: last month had a ¥5,000 budget
        XCTAssertTrue(element(app, "budget.cta").waitForExistence(timeout: 5), "this month has none yet")
        app.buttons["ledger.previous"].tap()
        XCTAssertTrue(waitForLabel(budgetValue(app), "5,000 yen"))
        XCTAssertTrue(element(app, "budget.closed").exists)
        XCTAssertFalse(app.buttons["budget.edit"].exists, "no editing a past month")
        XCTAssertFalse(element(app, "budget.cta").exists, "no setup prompt for a past month")
    }

    // MARK: Progress (B-05)

    /// Sample data: this month ¥5,198 spent. Budgets set so it lands in each state.
    @MainActor
    func testProgressStates() {
        let app = launch(seed: true)
        XCTAssertTrue(app.buttons["budget.cta.button"].waitForExistence(timeout: 5))

        // On track: ¥200,000 → 2% used, ¥194,802 left, weekly box with a date range.
        setBudget(app, "200000", fromPrompt: true)
        XCTAssertTrue(waitForLabel(element(app, "budget.status"), "2% used"))
        XCTAssertTrue(element(app, "budget.left").label.contains("194,802 yen"), element(app, "budget.left").label)
        let week = element(app, "budget.week")
        XCTAssertTrue(week.exists)
        XCTAssertTrue(week.label.contains("Available this week"), week.label)
        XCTAssertTrue(week.label.contains("今週使える金額 · "), "Japanese label paired on the date line: \(week.label)")
        XCTAssertTrue(week.label.contains("day"), "shows the days it covers: \(week.label)")
        XCTAssertTrue(week.label.contains("remaining in") || week.label.contains("last day"), week.label)

        // Close: ¥6,000 → 86%, said in words, not only color.
        setBudget(app, "6000")
        XCTAssertTrue(waitForLabel(element(app, "budget.status"), "86% used · close to budget"))
        XCTAssertTrue(element(app, "budget.left").label.contains("802 yen"))

        // Over: ¥5,000 → 103% (not clamped), over by ¥198, nothing available this week.
        setBudget(app, "5000")
        XCTAssertTrue(waitForLabel(element(app, "budget.status"), "103% used · over budget"))
        XCTAssertTrue(element(app, "budget.over").label.contains("198 yen"), element(app, "budget.over").label)
        XCTAssertTrue(element(app, "budget.week.amount").label.hasPrefix("0 yen"), element(app, "budget.week.amount").label)
        XCTAssertTrue(element(app, "budget.week").label.contains("used up"), element(app, "budget.week").label)

        // A new manual expense updates the progress straight away.
        app.buttons["ledger.add"].tap()
        let amount = app.textFields["review.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("802")
        app.buttons["review.save"].tap()
        XCTAssertTrue(waitForLabel(element(app, "budget.status"), "120% used · over budget"))
        XCTAssertTrue(element(app, "budget.over").label.contains("1,000 yen"))
    }

    /// Last month (sample: ¥3,278 of ¥5,000): the result, view only, no weekly box.
    @MainActor
    func testPastMonthProgress() {
        let app = launch(seed: true)
        XCTAssertTrue(app.buttons["ledger.previous"].waitForExistence(timeout: 5))
        app.buttons["ledger.previous"].tap()
        XCTAssertTrue(waitForLabel(element(app, "budget.status"), "Within budget · 65% used"))
        XCTAssertTrue(element(app, "budget.left").label.contains("Saved") && element(app, "budget.left").label.contains("1,722 yen"),
                      element(app, "budget.left").label)
        XCTAssertFalse(element(app, "budget.week").exists, "no weekly allowance for a past month")
    }

    /// The card's "Budget alert settings" opens Settings at the alerts, which explain both
    /// thresholds. Past months have no such button.
    @MainActor
    func testAlertSettingsLinkOpensSettings() {
        let app = launch(seed: true)
        XCTAssertTrue(app.buttons["budget.cta.button"].waitForExistence(timeout: 5))
        setBudget(app, "200000", fromPrompt: true)
        let link = app.buttons["budget.alertSettings"]
        var swipes = 0
        while !link.isHittable, swipes < 6 { app.swipeUp(); swipes += 1 }
        link.tap()
        XCTAssertTrue(app.switches["settings.alerts"].waitForExistence(timeout: 5))
        let thresholds = element(app, "settings.alerts.thresholds")
        XCTAssertTrue(thresholds.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '80%'")).count > 0)

        app.tabBars.buttons["Ledger"].tap()
        app.buttons["ledger.previous"].tap()
        XCTAssertTrue(element(app, "budget.closed").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["budget.alertSettings"].exists, "no alerts link for a past month")
    }

    @MainActor
    private func setBudget(_ app: XCUIApplication, _ value: String, fromPrompt: Bool = false) {
        app.buttons[fromPrompt ? "budget.cta.button" : "budget.edit"].tap()
        let amount = app.textFields["budget.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        type(value, into: amount, clearing: true)
        app.buttons["budget.save"].tap()
        XCTAssertTrue(app.buttons["budget.edit"].waitForExistence(timeout: 5))
    }

    // MARK: Helpers

    @MainActor
    private func launch(seed: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KAKEIBO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KAKEIBO_NO_REFINER"] = "1"
        if seed { app.launchEnvironment["KAKEIBO_SEED_SAMPLE"] = "1" }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_JP"]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor
    /// Spent against the budget, read as one element ending in the budget: "¥5,198 spent of, 200,000 yen".
    private func budgetValue(_ app: XCUIApplication) -> XCUIElement {
        element(app, "budget.value")
    }

    @MainActor
    private func budgetValueExistsBehindSheet(_ app: XCUIApplication) -> Bool {
        app.buttons["budget.cancel"].tap()
        return budgetValue(app).waitForExistence(timeout: 3)
    }

    @MainActor
    private func type(_ text: String, into field: XCUIElement, clearing: Bool = false) {
        field.tap()
        if clearing, let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    @MainActor
    /// Waits until the element's label ends with `label` (the amount at the end of the row).
    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label ENDSWITH %@ OR label == %@", label, label)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }
}
