import XCTest

/// The budget alert switch and the iOS permission in Settings (v1.1, B-06).
///
/// The app uses an in-memory notification center in UI tests (`KAKEIBO_NOTIFICATIONS` sets
/// what iOS "allows"), so the real permission prompt never appears. Real-device permission and
/// delivery are checked by hand in B-10.
final class BudgetAlertSettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // The Japanese test plan configuration runs only the smoke test; these tests force English.
        try XCTSkipIf(ProcessInfo.processInfo.environment["KAKEIBO_SMOKE_ONLY"] == "1", "Smoke test only in this configuration")
    }

    @MainActor
    func testOffByDefaultThenAllowed() {
        let app = openSettings()
        let toggle = app.switches["settings.alerts"]
        XCTAssertEqual(toggle.value as? String, "0", "off until the user turns it on")
        XCTAssertEqual(permission(app).label, "Not asked yet")

        turn(toggle)
        XCTAssertTrue(waitForLabel(permission(app), "Allowed"))
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertFalse(app.buttons["settings.alerts.openSettings"].exists)

        // Off again: the permission iOS gave stays as it is.
        turn(toggle)
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertEqual(permission(app).label, "Allowed")
    }

    @MainActor
    func testDeclinedPromptShowsTheSettingsLink() {
        let app = openSettings(notifications: "notDeterminedDeny")
        turn(app.switches["settings.alerts"])
        XCTAssertTrue(app.buttons["settings.alerts.openSettings"].waitForExistence(timeout: 3))
        XCTAssertEqual(permission(app).label, "Off")
    }

    @MainActor
    func testAlreadyDeniedShowsTheLinkOnlyWhenAlertsAreOn() {
        let app = openSettings(notifications: "denied")
        XCTAssertEqual(permission(app).label, "Off", "the real permission shows even with alerts off")
        XCTAssertFalse(app.buttons["settings.alerts.openSettings"].exists)

        let toggle = app.switches["settings.alerts"]
        turn(toggle)
        XCTAssertTrue(app.buttons["settings.alerts.openSettings"].waitForExistence(timeout: 3))

        turn(toggle)
        XCTAssertTrue(waitForAbsence(app.buttons["settings.alerts.openSettings"]))
    }

    // MARK: Helpers

    @MainActor
    private func openSettings(notifications: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KAKEIBO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KAKEIBO_NO_REFINER"] = "1"
        if let notifications { app.launchEnvironment["KAKEIBO_NOTIFICATIONS"] = notifications }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_JP"]
        app.launch()
        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.switches["settings.alerts"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func permission(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["settings.alerts.permission"]
    }

    /// Taps the switch itself: tapping the row's centre can land on the label.
    @MainActor
    private func turn(_ toggle: XCUIElement) {
        toggle.switches.firstMatch.tap()
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 3) == .completed
    }

    @MainActor
    private func waitForAbsence(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 3) == .completed
    }
}
