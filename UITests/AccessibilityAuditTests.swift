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

    @MainActor func testEditExpense() throws {
        try auditInBothModes("edit", seed: true) { app in
            let row = app.buttons["ledger.row"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 3))
        }
    }

    @MainActor func testManualEntry() throws {
        try auditInBothModes("manual entry") { app in
            app.buttons["ledger.add"].tap()
            XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 3))
        }
    }

    @MainActor func testScanReview() throws {
        try auditInBothModes("scan review", scan: true) { app in
            XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 30))
        }
    }

    // MARK: Helpers

    /// Launches in light, opens the screen, audits; then the same in dark.
    @MainActor
    private func auditInBothModes(_ screen: String, seed: Bool = false, scan: Bool = false,
                                  open: (XCUIApplication) -> Void) throws {
        for scheme in ["light", "dark"] {
            let app = launch(seed: seed, scan: scan, colorScheme: scheme)
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
    private func launch(seed: Bool = false, scan: Bool = false, colorScheme: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KAKEIBO_COLOR_SCHEME"] = colorScheme
        app.launchEnvironment["KAKEIBO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KAKEIBO_NO_REFINER"] = "1"
        if seed { app.launchEnvironment["KAKEIBO_SEED_SAMPLE"] = "1" }
        if scan {
            app.launchEnvironment["KAKEIBO_SCAN_IMAGE_PATH"] =
                Bundle(for: Self.self).path(forResource: "sample-receipt", ofType: "png")
        }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_JP"]
        app.launch()
        return app
    }
}
