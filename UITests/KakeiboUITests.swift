import XCTest

final class KakeiboUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() {
        let app = launch()
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// The simulator has no document camera: only "Choose photo" is offered.
    @MainActor
    func testSimulatorHidesCameraAndOffersPhoto() {
        let app = launch()
        XCTAssertTrue(app.buttons["scan.photo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["scan.camera"].exists)
    }

    // MARK: Scan

    /// A library photo goes through the real pipeline, into the review form, and is saved.
    @MainActor
    func testScanShowsProgressThenReviewAndSaves() {
        let app = launch(scan: true, ocrDelay: 3)
        XCTAssertTrue(app.buttons["scan.cancel"].waitForExistence(timeout: 5), "progress screen should appear")
        XCTAssertTrue(app.staticTexts["Reading your receipt"].exists)

        let amount = app.textFields["review.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 30), "review screen should appear")
        XCTAssertEqual(amount.value as? String, "754")
        XCTAssertTrue(app.staticTexts["Matches the receipt's total and payment"].exists)
        XCTAssertEqual(app.textFields["review.store"].value as? String, "サンプルマート中野店")
        XCTAssertTrue(app.staticTexts["review.time"].exists)
        XCTAssertTrue(app.staticTexts["review.invoice"].exists == false || app.staticTexts["review.invoice"].label.hasPrefix("T"))

        app.buttons["review.save"].tap()
        XCTAssertTrue(app.staticTexts["Saved ¥754"].waitForExistence(timeout: 5), "save confirmation")
        XCTAssertTrue(app.buttons["ledger.row"].waitForExistence(timeout: 5))
    }

    /// The sample store is not a known chain, so the category needs checking until one is picked.
    @MainActor
    func testUncertainCategoryIsHighlightedUntilChosen() {
        let app = launch(scan: true)
        XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["review.check.count"].exists)
        XCTAssertTrue(app.staticTexts["Check the category"].exists)

        scrollTo(app.buttons["category.groceries"], in: app).tap()
        XCTAssertFalse(app.staticTexts["Check the category"].exists)
        XCTAssertFalse(app.staticTexts["review.check.count"].exists)
    }

    @MainActor
    func testOCRTextAndPhotoZoom() {
        let app = launch(scan: true)
        XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 30))

        app.buttons["Text read from the photo"].firstMatch.tap()
        let text = app.staticTexts["review.ocrText"]
        XCTAssertTrue(text.waitForExistence(timeout: 2))
        XCTAssertTrue(text.label.contains("合計 ¥754"))

        app.buttons["review.photo"].tap()
        let close = app.buttons["photo.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 3))
    }

    /// Cancelling an unsaved scan asks first; "Keep editing" stays, "Discard" leaves nothing.
    @MainActor
    func testCancellingAScanAsksFirst() {
        let app = launch(scan: true)
        XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 30))

        app.buttons["review.cancel"].tap()
        XCTAssertTrue(app.buttons["confirm.cancel"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Discard this scan?"].exists)
        app.buttons["confirm.cancel"].tap()
        XCTAssertTrue(app.textFields["review.amount"].exists)

        app.buttons["review.cancel"].tap()
        app.buttons["confirm.action"].tap()
        XCTAssertTrue(app.buttons["scan.photo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ledger.row"].exists)
    }

    /// Cancel during reading returns to the ledger with nothing kept.
    @MainActor
    func testCancelDuringScan() {
        let app = launch(scan: true, ocrDelay: 20)
        let cancel = app.buttons["scan.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(app.buttons["scan.photo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["review.amount"].exists)
    }

    // MARK: Manual add, edit, delete

    @MainActor
    func testManualAddThenEditThenDelete() {
        let app = launch()
        app.buttons["ledger.add"].tap()
        XCTAssertTrue(app.staticTexts["Add expense"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["review.photo"].exists, "manual entry has no photo section")
        XCTAssertFalse(app.buttons["review.save"].isEnabled, "no amount yet")
        XCTAssertTrue(app.staticTexts["Enter the amount to save"].exists)

        let amount = app.textFields["review.amount"]
        amount.tap()
        amount.typeText("880")
        let store = app.textFields["review.store"]
        store.tap()
        store.typeText("Cafe Poem")
        app.buttons["review.save"].tap()
        XCTAssertTrue(app.staticTexts["Saved ¥880"].waitForExistence(timeout: 5))

        // Edit: change the amount.
        let row = app.buttons["ledger.row"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["Edit expense"].waitForExistence(timeout: 3))
        XCTAssertEqual(amount.value as? String, "880")
        amount.tap()
        amount.typeText("0")
        app.buttons["review.save"].tap()
        XCTAssertTrue(app.staticTexts["Saved ¥8,800"].waitForExistence(timeout: 5))

        // Delete with the in-app confirmation.
        row.tap()
        let delete = scrollTo(app.buttons["review.delete"], in: app)
        delete.tap()
        XCTAssertTrue(app.staticTexts["Delete this expense?"].waitForExistence(timeout: 2))
        app.buttons["confirm.action"].tap()
        XCTAssertTrue(app.staticTexts["Expense deleted"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ledger.row"].exists)
    }

    @MainActor
    func testCancellingUnchangedManualEntryDoesNotAsk() {
        let app = launch()
        app.buttons["ledger.add"].tap()
        XCTAssertTrue(app.buttons["review.cancel"].waitForExistence(timeout: 3))
        app.buttons["review.cancel"].tap()
        XCTAssertFalse(app.buttons["confirm.action"].exists)
        XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 3))
    }

    // MARK: Helpers

    /// Launches with an empty in-memory ledger in English, without the on-device model.
    /// With `scan`, a scan of the bundled made-up receipt starts at once.
    @MainActor
    private func launch(scan: Bool = false, ocrDelay: Double? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KAKEIBO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KAKEIBO_NO_REFINER"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_JP"]
        if scan {
            let path = Bundle(for: Self.self).path(forResource: "sample-receipt", ofType: "png")
            XCTAssertNotNil(path, "sample-receipt.png missing from the UI test bundle")
            app.launchEnvironment["KAKEIBO_SCAN_IMAGE_PATH"] = path
        }
        if let ocrDelay { app.launchEnvironment["KAKEIBO_SCAN_OCR_DELAY"] = String(ocrDelay) }
        app.launch()
        return app
    }

    @MainActor
    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        var tries = 0
        while !element.isHittable, tries < 8 {
            app.swipeUp()
            tries += 1
        }
        return element
    }
}
