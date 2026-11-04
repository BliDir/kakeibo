import XCTest

/// Runs Xcode's accessibility audit (the same checks as Accessibility Inspector) on the main
/// screens, in light and dark mode. Any issue fails the test, with the element and what is wrong.
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
    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.appearance = .light
    }

    @MainActor func testLedger() throws {
        let app = launch(seed: true)
        XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 5))
        try audit(app, "ledger")
    }

    @MainActor func testEmptyLedger() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 5))
        try audit(app, "empty ledger")
    }

    @MainActor func testSummary() throws {
        let app = launch(seed: true)
        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["summary.total"].waitForExistence(timeout: 5))
        try audit(app, "summary")
    }

    @MainActor func testSettings() throws {
        let app = launch()
        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.buttons["settings.language"].waitForExistence(timeout: 5))
        try audit(app, "settings")
    }

    @MainActor func testEditExpense() throws {
        let app = launch(seed: true)
        let row = app.buttons["ledger.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 3))
        try audit(app, "edit")
    }

    @MainActor func testManualEntry() throws {
        let app = launch()
        app.buttons["ledger.add"].tap()
        XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 3))
        try audit(app, "manual entry")
    }

    @MainActor func testScanReview() throws {
        let app = launch(scan: true)
        XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 30))
        try audit(app, "scan review")
    }

    // MARK: Helpers

    /// Audits the current screen. `KAKEIBO_AUDIT_LOG_ONLY=1` (as `TEST_RUNNER_…`) logs issues without failing.
    @MainActor
    private func audit(_ app: XCUIApplication, _ screen: String) throws {
        try audit(app, screen, mode: "light")
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }
        sleep(1)   // let the app redraw in dark mode
        try audit(app, screen, mode: "dark")
    }

    @MainActor
    private func audit(_ app: XCUIApplication, _ screen: String, mode: String) throws {
        let logOnly = ProcessInfo.processInfo.environment["KAKEIBO_AUDIT_LOG_ONLY"] == "1"
        try app.performAccessibilityAudit(for: Self.auditTypes) { issue in
            if issue.auditType == .textClipped, issue.element.map({ Self.isSpokenAmount($0.label) }) ?? true {
                return true
            }
            let element = issue.element.map { "\($0.elementType.rawValue) '\($0.identifier)' '\($0.label)'" } ?? "none"
            let line = "AUDIT [\(screen), \(mode)] \(issue.auditType): \(issue.compactDescription) — \(element)"
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
    private func launch(seed: Bool = false, scan: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
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
