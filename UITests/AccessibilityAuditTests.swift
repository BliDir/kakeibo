import XCTest

/// Runs Xcode's accessibility audit (the same checks as Accessibility Inspector) on the main
/// screens. Any issue fails the test, with the element and what is wrong.
///
/// Each screen is audited in light and in dark mode: the app is launched once per mode with
/// `KAKEIBO_COLOR_SCHEME` (switching the simulator's appearance does not reach the app in tests).
///
/// Two checks are handled differently, on purpose:
/// - Contrast is not audited here. The audit samples screen pixels over each element's whole
///   frame (chip borders, icons, antialiased small text) and flags pairs that pass on paper,
///   e.g. Text on Field (15:1). Contrast is checked exactly, for every text/background pair in
///   light and dark, by `python3 scripts/design-tokens.py --check` (run in CI).
/// - "Text clipped" is ignored for amounts whose VoiceOver label is the spoken form ("5,198 yen"):
///   the audit measures that label against the shorter visible text ("¥5,198"), and for
///   predictions about larger sizes that name no element. `ScreenshotTourTests` checks every
///   screen at XXXL and AX5 by eye instead.
/// - "Potentially inaccessible text" with no element is ignored. The audit reads text off the
///   screenshot, and ledger rows that scroll under the floating scan buttons and the glass tab bar
///   show half-covered text it cannot match to an element. Each row is one labelled button
///   (store, category, payment, amount, date), and the same screen scrolled to the end, with
///   nothing under the bars, audits clean. Issues that name an element still fail.
final class AccessibilityAuditTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        // The Japanese test plan configuration runs only the smoke test; these tests force English.
        try XCTSkipIf(ProcessInfo.processInfo.environment["KAKEIBO_SMOKE_ONLY"] == "1", "Smoke test only in this configuration")
    }

    @MainActor func testLedger() throws {
        try auditInBothModes("ledger", seed: true) { app in
            XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 5))
        }
    }

    @MainActor func testEmptyLedger() throws {
        try auditInBothModes("empty ledger") { app in
            XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 5))
        }
    }

    @MainActor func testSummary() throws {
        try auditInBothModes("summary", seed: true) { app in
            app.tabBars.buttons.element(boundBy: 1).tap()
            XCTAssertTrue(app.staticTexts["summary.total"].waitForExistence(timeout: 5))
        }
    }

    @MainActor func testSettings() throws {
        try auditInBothModes("settings") { app in
            app.tabBars.buttons.element(boundBy: 2).tap()
            XCTAssertTrue(app.buttons["settings.language"].waitForExistence(timeout: 5))
        }
    }

    /// Budget alerts turned on while iOS has notifications off: the warning and the Settings link.
    @MainActor func testSettingsAlertsDenied() throws {
        try auditInBothModes("settings, alerts denied", notifications: "denied") { app in
            app.tabBars.buttons.element(boundBy: 2).tap()
            let toggle = app.switches["settings.alerts"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            toggle.switches.firstMatch.tap()
            XCTAssertTrue(app.buttons["settings.alerts.openSettings"].waitForExistence(timeout: 3))
        }
    }

    // Budget states (B-08). The sample month has ¥5,198 spent.

    @MainActor func testBudgetOnTrack() throws {
        try auditInBothModes("budget on track", seed: true) { app in
            setBudget(app, "20000")
        }
    }

    /// 86% used: "close to budget", with the 80% banner on top.
    @MainActor func testBudgetNearWithBanner() throws {
        try auditInBothModes("budget near, banner", seed: true) { app in
            setBudget(app, "6000")
            XCTAssertTrue(app.descendants(matching: .any)["budget.alert.80"].firstMatch.waitForExistence(timeout: 3))
        }
    }

    /// 103% used: "over budget", with the 100% banner on top.
    @MainActor func testBudgetOverWithBanner() throws {
        try auditInBothModes("budget over, banner", seed: true) { app in
            setBudget(app, "5000")
            XCTAssertTrue(app.descendants(matching: .any)["budget.alert.100"].firstMatch.waitForExistence(timeout: 3))
        }
    }

    /// Last month's ¥5,000 budget (sample data), view only.
    @MainActor func testPastMonthBudget() throws {
        try auditInBothModes("past month budget", seed: true) { app in
            XCTAssertTrue(app.buttons["ledger.previous"].waitForExistence(timeout: 5))
            app.buttons["ledger.previous"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["budget.closed"].firstMatch.waitForExistence(timeout: 3))
        }
    }

    @MainActor func testBudgetSheetInvalidAmount() throws {
        try auditInBothModes("budget sheet, invalid") { app in
            app.buttons["budget.cta.button"].tap()
            let field = app.textFields["budget.amount"]
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            field.typeText("0")
            XCTAssertTrue(app.descendants(matching: .any)["budget.problem"].firstMatch.waitForExistence(timeout: 3))
        }
    }

    @MainActor func testExport() throws {
        try auditInBothModes("export", seed: true) { app in
            app.buttons["ledger.export"].tap()
            XCTAssertTrue(app.buttons["export.choice.month"].waitForExistence(timeout: 5))
        }
    }

    @MainActor func testExportFailed() throws {
        try auditInBothModes("export failed", extra: ["KAKEIBO_FAIL_EXPORT": "1"]) { app in
            app.buttons["ledger.export"].tap()
            XCTAssertTrue(app.buttons["export.retry"].waitForExistence(timeout: 5))
        }
    }

    @MainActor func testExpenseDetails() throws {
        try auditInBothModes("expense details", seed: true) { app in
            let row = app.buttons["ledger.row"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            XCTAssertTrue(app.buttons["detail.edit"].waitForExistence(timeout: 3))
        }
    }

    @MainActor func testEditExpense() throws {
        try auditInBothModes("edit", seed: true) { app in
            let row = app.buttons["ledger.row"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            app.buttons["detail.edit"].tap()
            XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 3))
        }
    }

    @MainActor func testDeleteConfirmation() throws {
        try auditInBothModes("delete confirmation", seed: true) { app in
            let row = app.buttons["ledger.row"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            app.buttons["detail.delete"].tap()
            XCTAssertTrue(app.buttons["confirm.action"].waitForExistence(timeout: 3))
        }
    }

    @MainActor func testDuplicateWarning() throws {
        try auditInBothModes("duplicate warning", seed: true) { app in
            self.typeManualEntry(app, amount: "1078", store: "スターバックス")
            XCTAssertTrue(app.buttons["duplicate.view"].waitForExistence(timeout: 3))
        }
    }

    @MainActor func testSaveFailure() throws {
        try auditInBothModes("save failure", extra: ["KAKEIBO_FAIL_SAVES": "1"]) { app in
            self.typeManualEntry(app, amount: "640", store: "Soba Stand")
            XCTAssertTrue(app.buttons["failure.retry"].waitForExistence(timeout: 3))
        }
    }

    @MainActor func testDiscardConfirmation() throws {
        try auditInBothModes("discard confirmation") { app in
            app.buttons["ledger.add"].tap()
            let amount = app.textFields["review.amount"]
            XCTAssertTrue(amount.waitForExistence(timeout: 3))
            amount.tap()
            amount.typeText("500")
            app.buttons["review.cancel"].tap()
            XCTAssertTrue(app.buttons["confirm.action"].waitForExistence(timeout: 3))
        }
    }

    @MainActor func testManualEntry() throws {
        try auditInBothModes("manual entry") { app in
            app.buttons["ledger.add"].tap()
            XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 3))
        }
    }

    @MainActor func testBudgetSheet() throws {
        try auditInBothModes("budget sheet") { app in
            app.buttons["budget.cta.button"].tap()
            XCTAssertTrue(app.textFields["budget.amount"].waitForExistence(timeout: 3))
        }
    }

    @MainActor func testScanReadError() throws {
        try auditInBothModes("scan read error", extra: ["KAKEIBO_SCAN_IMAGE_PATH": Bundle(for: Self.self).path(forResource: "Info", ofType: "plist") ?? ""]) { app in
            XCTAssertTrue(app.buttons["scan.error.manual"].waitForExistence(timeout: 10))
        }
    }

    @MainActor func testCameraDenied() throws {
        try auditInBothModes("camera denied", extra: ["KAKEIBO_SHOW_CAMERA_DENIED": "1"]) { app in
            XCTAssertTrue(app.buttons["camera.denied.openSettings"].waitForExistence(timeout: 5))
        }
    }

    @MainActor func testScanReview() throws {
        try auditInBothModes("scan review", scan: true) { app in
            XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 30))
        }
    }

    // MARK: Helpers

    /// Opens a manual entry, types an amount and a store, and taps Save.
    @MainActor
    private func typeManualEntry(_ app: XCUIApplication, amount: String, store: String) {
        XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 5))
        app.buttons["ledger.add"].tap()
        let amountField = app.textFields["review.amount"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 3))
        amountField.tap()
        amountField.typeText(amount)
        let storeField = app.textFields["review.store"]
        storeField.tap()
        storeField.typeText(store)
        app.buttons["review.save"].tap()
    }

    /// Sets this month's budget from the setup prompt and waits for the ledger.
    @MainActor
    private func setBudget(_ app: XCUIApplication, _ amount: String) {
        XCTAssertTrue(app.buttons["budget.cta.button"].waitForExistence(timeout: 5))
        app.buttons["budget.cta.button"].tap()
        let field = app.textFields["budget.amount"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText(amount)
        app.buttons["budget.save"].tap()
        XCTAssertTrue(app.buttons["budget.edit"].waitForExistence(timeout: 5))
    }

    /// Launches in light, opens the screen, audits; then the same in dark.
    @MainActor
    private func auditInBothModes(_ screen: String, seed: Bool = false, scan: Bool = false,
                                  notifications: String? = nil, extra: [String: String] = [:],
                                  open: (XCUIApplication) -> Void) throws {
        for scheme in ["light", "dark"] {
            let app = launch(seed: seed, scan: scan, notifications: notifications, extra: extra, colorScheme: scheme)
            open(app)
            try audit(app, "\(screen), \(scheme)")
            app.terminate()
        }
    }

    /// Audits the current screen. `KAKEIBO_AUDIT_LOG_ONLY=1` (as `TEST_RUNNER_…`) logs issues without failing.
    @MainActor
    private func audit(_ app: XCUIApplication, _ screen: String) throws {
        let logOnly = ProcessInfo.processInfo.environment["KAKEIBO_AUDIT_LOG_ONLY"] == "1"
        try app.performAccessibilityAudit(for: Self.auditTypes) { issue in
            if issue.auditType == .textClipped, issue.element.map({ Self.isSpokenAmount($0.label) }) ?? true {
                return true
            }
            if issue.auditType == .elementDetection, issue.element == nil {
                return true
            }
            let element = issue.element.map { "\($0.elementType.rawValue) '\($0.identifier)' '\($0.label)'" } ?? "none"
            let line = "AUDIT [\(screen)] \(issue.auditType): \(issue.compactDescription) — \(element)"
            print(line)
            if !logOnly { XCTFail(line) }
            return true   // handled: keep auditing so every issue is reported
        }
    }

    static let auditTypes: XCUIAccessibilityAuditType = .all.subtracting(.contrast)

    /// "5,198 yen", "Save 754 yen", "Tax 消費税 259 yen".
    static func isSpokenAmount(_ label: String) -> Bool {
        label.range(of: #"\d yen\b"#, options: .regularExpression) != nil
    }

    @MainActor
    private func launch(seed: Bool = false, scan: Bool = false, notifications: String? = nil,
                        extra: [String: String] = [:], colorScheme: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KAKEIBO_COLOR_SCHEME"] = colorScheme
        app.launchEnvironment["KAKEIBO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KAKEIBO_NO_REFINER"] = "1"
        if seed { app.launchEnvironment["KAKEIBO_SEED_SAMPLE"] = "1" }
        if let notifications { app.launchEnvironment["KAKEIBO_NOTIFICATIONS"] = notifications }
        for (key, value) in extra { app.launchEnvironment[key] = value }
        if scan {
            app.launchEnvironment["KAKEIBO_SCAN_IMAGE_PATH"] =
                Bundle(for: Self.self).path(forResource: "sample-receipt", ofType: "png")
        }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_JP"]
        app.launch()
        return app
    }
}
