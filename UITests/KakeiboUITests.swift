import XCTest

final class KakeiboUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// The simulator has no document camera: only "Choose photo" is offered.
    @MainActor
    func testSimulatorHidesCameraAndOffersPhoto() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["scan.photo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["scan.camera"].exists)
    }

    /// A library photo goes through the real pipeline: progress screen, then the result.
    @MainActor
    func testPhotoScanShowsProgressThenResult() throws {
        let app = launchWithSampleReceipt(ocrDelay: 3)
        XCTAssertTrue(app.buttons["scan.cancel"].waitForExistence(timeout: 5), "progress screen should appear")
        XCTAssertTrue(app.staticTexts["Reading your receipt"].exists)
        let total = app.staticTexts["scan.result.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 30), "result should appear")
        XCTAssertEqual(total.label, "¥754")

        app.buttons["scan.result.done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["scan.photo"].waitForExistence(timeout: 5))
    }

    /// Cancel during reading returns to the ledger with nothing kept.
    @MainActor
    func testCancelDuringScan() throws {
        let app = launchWithSampleReceipt(ocrDelay: 20)
        let cancel = app.buttons["scan.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(app.buttons["scan.photo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["scan.result.total"].exists)
    }

    @MainActor
    /// Starts a scan of the bundled made-up receipt, with OCR slowed by `ocrDelay` seconds.
    private func launchWithSampleReceipt(ocrDelay: Double) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KAKEIBO_SCAN_OCR_DELAY"] = String(ocrDelay)
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_JP"]
        let path = Bundle(for: Self.self).path(forResource: "sample-receipt", ofType: "png")
        XCTAssertNotNil(path, "sample-receipt.png missing from the UI test bundle")
        app.launchEnvironment["KAKEIBO_SCAN_IMAGE_PATH"] = path
        app.launch()
        return app
    }
}
