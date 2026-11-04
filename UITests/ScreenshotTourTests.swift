import XCTest

/// Walks every screen in Japanese and English at three text sizes, and attaches a screenshot of
/// each: the default, the largest standard size (XXXL, the top of the Text Size slider) and the
/// largest accessibility size (AX5, with Larger Accessibility Sizes on). Used for the
/// localization (T-46) and accessibility (T-47) checks.
///
/// Skipped unless `KAKEIBO_SCREENSHOT_TOUR=1` reaches the test runner:
///
///     TEST_RUNNER_KAKEIBO_SCREENSHOT_TOUR=1 xcodebuild test -scheme Kakeibo \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:KakeiboUITests/ScreenshotTourTests -resultBundlePath tour.xcresult
///     xcrun xcresulttool export attachments --path tour.xcresult --output-path tour
final class ScreenshotTourTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KAKEIBO_SCREENSHOT_TOUR"] == "1",
                          "Set TEST_RUNNER_KAKEIBO_SCREENSHOT_TOUR=1 to take the screenshot tour")
    }

    enum TextSize: String {
        case `default`, XXXL, AX5

        var category: String? {
            switch self {
            case .default: nil
            case .XXXL: "UICTContentSizeCategoryXXXL"
            case .AX5: "UICTContentSizeCategoryAccessibilityXXXL"
            }
        }
    }

    @MainActor func testJapaneseDefaultSize() { tour(language: "ja", size: .default) }
    @MainActor func testJapaneseLargestStandardSize() { tour(language: "ja", size: .XXXL) }
    @MainActor func testJapaneseLargestAccessibilitySize() { tour(language: "ja", size: .AX5) }
    @MainActor func testEnglishDefaultSize() { tour(language: "en", size: .default) }
    @MainActor func testEnglishLargestStandardSize() { tour(language: "en", size: .XXXL) }
    @MainActor func testEnglishLargestAccessibilitySize() { tour(language: "en", size: .AX5) }

    // MARK: Tour

    @MainActor
    private func tour(language: String, size: TextSize) {
        let tag = "\(language)-\(size.rawValue)"

        // Ledger, Summary, Settings with sample data.
        var app = launch(language: language, size: size, seed: true)
        XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 5))
        shot(app, "\(tag)-01-ledger")
        app.swipeUp()
        shot(app, "\(tag)-02-ledger-scrolled")
        tab(app, 1)
        shot(app, "\(tag)-03-summary")
        app.swipeUp()
        shot(app, "\(tag)-04-summary-scrolled")
        tab(app, 2)
        shot(app, "\(tag)-05-settings")
        app.swipeUp()
        shot(app, "\(tag)-06-settings-scrolled")

        // Export sheet.
        tab(app, 0)
        app.swipeDown()
        app.buttons["ledger.export"].tap()
        if app.buttons["export.close"].waitForExistence(timeout: 3) {
            shot(app, "\(tag)-07-export")
            app.buttons["export.close"].tap()
        }

        // Edit an expense, its lower half, and the delete confirmation.
        let row = app.buttons["ledger.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 3))
        shot(app, "\(tag)-08-edit")
        let delete = scrollTo(app.buttons["review.delete"], in: app)
        shot(app, "\(tag)-09-edit-scrolled")
        delete.tap()
        if app.buttons["confirm.cancel"].waitForExistence(timeout: 2) {
            shot(app, "\(tag)-10-delete-confirm")
            app.buttons["confirm.cancel"].tap()
        }
        app.buttons["review.cancel"].tap()

        // Manual entry that duplicates a sample expense (same store, day and amount).
        app.buttons["ledger.add"].tap()
        let amount = app.textFields["review.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        shot(app, "\(tag)-11-manual")
        amount.tap()
        amount.typeText("1078")
        let store = app.textFields["review.store"]
        store.tap()
        store.typeText("スターバックス")
        app.buttons["review.save"].tap()
        if app.buttons["duplicate.cancel"].waitForExistence(timeout: 3) {
            shot(app, "\(tag)-12-duplicate")
            app.buttons["duplicate.cancel"].tap()
        }
        app.terminate()

        // Scan: progress, review, discard confirmation.
        app = launch(language: language, size: size, scan: true, ocrDelay: 4)
        if app.buttons["scan.cancel"].waitForExistence(timeout: 5) {
            shot(app, "\(tag)-13-scan-progress")
        }
        XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 30))
        shot(app, "\(tag)-14-scan-review")
        app.swipeUp()
        shot(app, "\(tag)-15-scan-review-scrolled")
        app.buttons["review.cancel"].tap()
        if app.buttons["confirm.cancel"].waitForExistence(timeout: 2) {
            shot(app, "\(tag)-16-discard-confirm")
        }
        app.terminate()

        // Empty ledger.
        app = launch(language: language, size: size)
        XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 5))
        shot(app, "\(tag)-17-ledger-empty")
        app.terminate()
    }

    // MARK: Helpers

    @MainActor
    private func launch(language: String, size: TextSize, seed: Bool = false, scan: Bool = false,
                        ocrDelay: Double? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KAKEIBO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KAKEIBO_NO_REFINER"] = "1"
        if seed { app.launchEnvironment["KAKEIBO_SEED_SAMPLE"] = "1" }
        if scan {
            app.launchEnvironment["KAKEIBO_SCAN_IMAGE_PATH"] =
                Bundle(for: Self.self).path(forResource: "sample-receipt", ofType: "png")
        }
        if let ocrDelay { app.launchEnvironment["KAKEIBO_SCAN_OCR_DELAY"] = String(ocrDelay) }
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "ja" ? "ja_JP" : "en_JP"]
        if let category = size.category {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", category]
        }
        app.launch()
        return app
    }

    /// Tabs by position, so the same code works in both languages.
    @MainActor
    private func tab(_ app: XCUIApplication, _ index: Int) {
        app.tabBars.buttons.element(boundBy: index).tap()
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        var tries = 0
        while !element.isHittable, tries < 10 {
            app.swipeUp()
            tries += 1
        }
        return element
    }
}
