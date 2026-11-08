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
///
/// For dark mode, add `TEST_RUNNER_KAKEIBO_TOUR_DARK=1`: every screen is then taken in dark mode.
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
            _ = app.buttons["export.choice.month"].waitForExistence(timeout: 3)
            shot(app, "\(tag)-07-export")
            if app.buttons["export.choice.year"].exists {
                app.buttons["export.choice.year"].tap()
                shot(app, "\(tag)-07a-export-year")
            }
            app.buttons["export.close"].tap()
        }

        // Budget (v1.1): the sheet from the setup prompt, then last month's read-only budget.
        let setBudget = app.buttons["budget.cta.button"]
        if setBudget.waitForExistence(timeout: 3) {
            setBudget.tap()
            if app.textFields["budget.amount"].waitForExistence(timeout: 3) {
                app.textFields["budget.amount"].typeText("200000")
                app.switches["budget.template"].switches.firstMatch.tap()
                shot(app, "\(tag)-07b-budget-sheet")
                app.buttons["budget.save"].tap()
                if app.buttons["budget.edit"].waitForExistence(timeout: 3) {
                    app.swipeUp()
                    shot(app, "\(tag)-07d-budget-progress")
                    app.swipeDown()
                }
            }
        }
        app.buttons["ledger.previous"].tap()
        shot(app, "\(tag)-07c-past-month-budget")
        app.buttons["ledger.next"].tap()

        // Budget states (B-08). The sample month has ¥5,198 spent: a ¥6,000 budget is 86%
        // (close, 80% banner), ¥5,000 is 103% (over, 100% banner). Then a typing error.
        if editBudget(app, to: "6000") {
            shot(app, "\(tag)-07e-budget-near-banner")
            dismissAlert(app)
            shot(app, "\(tag)-07f-budget-near")
        }
        if editBudget(app, to: "5000") {
            shot(app, "\(tag)-07g-budget-over-banner")
            dismissAlert(app)
            app.swipeUp()
            shot(app, "\(tag)-07h-budget-over-scrolled")
            app.swipeDown()
        }
        if app.buttons["budget.edit"].waitForExistence(timeout: 3) {
            app.buttons["budget.edit"].tap()
            let field = app.textFields["budget.amount"]
            if field.waitForExistence(timeout: 3) {
                replace(field, with: "0")
                shot(app, "\(tag)-07i-budget-invalid")
                app.buttons["budget.cancel"].tap()
            }
        }

        // An expense's details, the delete confirmation, then its edit form and lower half.
        let row = app.buttons["ledger.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        XCTAssertTrue(app.buttons["detail.edit"].waitForExistence(timeout: 3))
        shot(app, "\(tag)-08a-details")
        let delete = scrollTo(app.buttons["detail.delete"], in: app)
        shot(app, "\(tag)-08b-details-scrolled")
        delete.tap()
        if app.buttons["confirm.cancel"].waitForExistence(timeout: 2) {
            shot(app, "\(tag)-10-delete-confirm")
            app.buttons["confirm.cancel"].tap()
        }
        app.buttons["detail.edit"].tap()
        XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 3))
        shot(app, "\(tag)-08-edit")
        app.swipeUp()
        shot(app, "\(tag)-09-edit-scrolled")
        app.buttons["review.cancel"].tap()
        if app.buttons["detail.back"].waitForExistence(timeout: 2) {
            app.buttons["detail.back"].tap()
        }

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
        if app.buttons["review.more"].exists {
            app.buttons["review.more"].tap()
            shot(app, "\(tag)-15b-scan-review-more")
        }
        app.buttons["review.cancel"].tap()
        if app.buttons["confirm.cancel"].waitForExistence(timeout: 2) {
            shot(app, "\(tag)-16-discard-confirm")
        }
        app.terminate()

        // Save failure (UI-04): the first save fails.
        app = launch(language: language, size: size, extra: ["KAKEIBO_FAIL_SAVES": "1"])
        app.buttons["ledger.add"].tap()
        let failAmount = app.textFields["review.amount"]
        if failAmount.waitForExistence(timeout: 3) {
            failAmount.tap()
            failAmount.typeText("640")
            app.buttons["review.save"].tap()
            if app.buttons["failure.retry"].waitForExistence(timeout: 3) {
                shot(app, "\(tag)-16d-save-failure")
            }
        }
        app.terminate()

        // Receipt not readable (UI-03): a file that is not an image.
        app = launch(language: language, size: size,
                     extra: ["KAKEIBO_SCAN_IMAGE_PATH": Bundle(for: Self.self).path(forResource: "Info", ofType: "plist") ?? ""])
        if app.buttons["scan.error.manual"].waitForExistence(timeout: 10) {
            shot(app, "\(tag)-16b-scan-read-error")
        }
        app.terminate()

        // Camera access off (UI-03).
        app = launch(language: language, size: size, extra: ["KAKEIBO_SHOW_CAMERA_DENIED": "1"])
        if app.buttons["camera.denied.openSettings"].waitForExistence(timeout: 5) {
            shot(app, "\(tag)-16c-camera-denied")
        }
        app.terminate()

        // Empty ledger, its empty Summary, and an export with nothing in it.
        app = launch(language: language, size: size)
        XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 5))
        shot(app, "\(tag)-17-ledger-empty")
        tab(app, 1)
        shot(app, "\(tag)-17a-summary-empty")
        tab(app, 0)
        app.buttons["ledger.export"].tap()
        if app.buttons["export.choice.month"].waitForExistence(timeout: 3) {
            shot(app, "\(tag)-17b-export-empty")
        }
        app.terminate()

        // Export that cannot write its file (UI-05).
        app = launch(language: language, size: size, extra: ["KAKEIBO_FAIL_EXPORT": "1"])
        XCTAssertTrue(app.buttons["ledger.export"].waitForExistence(timeout: 5))
        app.buttons["ledger.export"].tap()
        if app.buttons["export.retry"].waitForExistence(timeout: 3) {
            shot(app, "\(tag)-17c-export-failed")
        }
        app.terminate()

        // Budget alerts on while iOS has notifications off: the warning and the Settings link.
        app = launch(language: language, size: size, notifications: "denied")
        tab(app, 2)
        let alerts = app.switches["settings.alerts"]
        if alerts.waitForExistence(timeout: 5) {
            alerts.switches.firstMatch.tap()
            _ = app.buttons["settings.alerts.openSettings"].waitForExistence(timeout: 3)
            shot(app, "\(tag)-18-settings-alerts-denied")
            app.swipeUp()
            shot(app, "\(tag)-19-settings-alerts-denied-scrolled")
        }
        app.terminate()

        // Budget insights (BI-04): card, analysis and filtered ledger in each state.
        for (index, state) in ["onPace", "over", "closed", "limited"].enumerated() {
            let name = "\(tag)-2\(index)-insight-\(state)"
            app = launch(language: language, size: size, notifications: "denied", extra: ["KAKEIBO_SEED_INSIGHT": state])
            dismissAlert(app)
            if state == "closed", app.buttons["ledger.previous"].waitForExistence(timeout: 5) {
                app.buttons["ledger.previous"].tap()
            }
            guard scrollTo(app.buttons["insight.see"], in: app).exists else { app.terminate(); continue }
            shot(app, "\(name)-card")
            app.buttons["insight.see"].tap()
            if app.buttons["analysis.back"].waitForExistence(timeout: 3) {
                shot(app, "\(name)-analysis")
                for page in 1...3 {
                    app.swipeUp()
                    shot(app, "\(name)-analysis-\(page)")
                }
            }
            if state == "over" {
                for _ in 0..<4 { app.swipeDown() }
                let driver = app.buttons["analysis.driver"].firstMatch
                if scrollTo(driver, in: app).exists {
                    driver.tap()
                    if app.buttons["filtered.back"].waitForExistence(timeout: 3) { shot(app, "\(name)-filtered") }
                }
            }
            app.terminate()
        }
    }

    /// Opens the budget sheet, types a new amount and saves. True when back on the ledger.
    @MainActor
    private func editBudget(_ app: XCUIApplication, to amount: String) -> Bool {
        guard app.buttons["budget.edit"].waitForExistence(timeout: 3) else { return false }
        app.buttons["budget.edit"].tap()
        let field = app.textFields["budget.amount"]
        guard field.waitForExistence(timeout: 3) else { return false }
        replace(field, with: amount)
        app.buttons["budget.save"].tap()
        return app.buttons["budget.edit"].waitForExistence(timeout: 3)
    }

    @MainActor
    private func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    @MainActor
    private func dismissAlert(_ app: XCUIApplication) {
        let dismiss = app.buttons["budget.alert.dismiss"]
        if dismiss.waitForExistence(timeout: 3) { dismiss.tap() }
    }

    // MARK: Helpers

    @MainActor
    private func launch(language: String, size: TextSize, seed: Bool = false, scan: Bool = false,
                        ocrDelay: Double? = nil, notifications: String? = nil,
                        extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KAKEIBO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KAKEIBO_NO_REFINER"] = "1"
        if ProcessInfo.processInfo.environment["KAKEIBO_TOUR_DARK"] == "1" {
            app.launchEnvironment["KAKEIBO_COLOR_SCHEME"] = "dark"
        }
        if seed { app.launchEnvironment["KAKEIBO_SEED_SAMPLE"] = "1" }
        if let notifications { app.launchEnvironment["KAKEIBO_NOTIFICATIONS"] = notifications }
        for (key, value) in extra { app.launchEnvironment[key] = value }
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
