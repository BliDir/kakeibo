import XCTest

/// Camera off and receipt not readable (UI-03): what each offers, and that each way out leaves
/// the session in the right state. The simulator has no camera, so the camera-off sheet is
/// opened with the Debug hook `KAKEIBO_SHOW_CAMERA_DENIED`.
final class ScanStatesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // The Japanese test plan configuration runs only the smoke test; these tests force English.
        try XCTSkipIf(ProcessInfo.processInfo.environment["KAKEIBO_SMOKE_ONLY"] == "1", "Smoke test only in this configuration")
    }

    // MARK: Read error

    @MainActor
    func testUnreadableImageOffersAnotherPhotoAndManual() {
        let app = launch(unreadable: true)
        XCTAssertTrue(element(app, "scan.error").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["A clearer photo should do it"].exists)
        XCTAssertTrue(app.buttons["scan.error.photo"].isEnabled, "choose another photo")
        XCTAssertFalse(app.buttons["scan.error.scanAgain"].exists, "no camera on the simulator")

        // Enter manually: the scan is dropped and an empty manual form opens.
        app.buttons["scan.error.manual"].tap()
        let amount = app.textFields["review.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        // A fresh manual form, nothing from the failed scan: no amount, so nothing to save.
        XCTAssertFalse(app.buttons["review.save"].isEnabled)
        XCTAssertFalse(element(app, "scan.error").exists)

        // Cancelling it goes back to an empty ledger.
        app.buttons["review.cancel"].tap()
        XCTAssertTrue(app.buttons["scan.photo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ledger.row"].exists)
    }

    @MainActor
    func testUnreadableImageCloseReturnsToLedger() {
        let app = launch(unreadable: true)
        XCTAssertTrue(element(app, "scan.error").waitForExistence(timeout: 10))
        app.buttons["scan.error.close"].tap()
        XCTAssertTrue(app.buttons["scan.photo"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "scan.error").exists)
        XCTAssertFalse(app.buttons["ledger.row"].exists)
    }

    // MARK: Camera off

    @MainActor
    func testCameraDeniedOffersSettingsPhotoAndManual() {
        let app = launch(cameraDenied: true)
        XCTAssertTrue(element(app, "camera.denied").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["camera.denied.openSettings"].exists)
        XCTAssertTrue(app.buttons["camera.denied.photo"].exists)

        // Add manually: the sheet goes and the manual form opens.
        app.buttons["camera.denied.manual"].tap()
        XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "camera.denied").exists)
    }

    @MainActor
    func testCameraDeniedClose() {
        let app = launch(cameraDenied: true)
        XCTAssertTrue(element(app, "camera.denied").waitForExistence(timeout: 5))
        app.buttons["camera.denied.close"].tap()
        XCTAssertTrue(waitForAbsence(element(app, "camera.denied")))
        XCTAssertTrue(app.buttons["scan.photo"].isHittable)
    }

    // MARK: Helpers

    @MainActor
    private func launch(unreadable: Bool = false, cameraDenied: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KAKEIBO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KAKEIBO_NO_REFINER"] = "1"
        if unreadable {
            // Not an image: the photo path fails at once with "couldn't read this image".
            let path = Bundle(for: Self.self).path(forResource: "Info", ofType: "plist")
            XCTAssertNotNil(path)
            app.launchEnvironment["KAKEIBO_SCAN_IMAGE_PATH"] = path
        }
        if cameraDenied { app.launchEnvironment["KAKEIBO_SHOW_CAMERA_DENIED"] = "1" }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_JP"]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor
    private func waitForAbsence(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 5) == .completed
    }
}
