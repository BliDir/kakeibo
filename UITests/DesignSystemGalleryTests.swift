import XCTest

/// The design system gallery (UI-01) in light and dark: opens, and attaches a screenshot of each
/// part so component changes can be reviewed in both themes. The gallery is a Debug-only screen
/// (the hammer button on the ledger), so this runs only against Debug builds, as all UI tests do.
final class DesignSystemGalleryTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // The Japanese test plan configuration runs only the smoke test.
        try XCTSkipIf(ProcessInfo.processInfo.environment["KAKEIBO_SMOKE_ONLY"] == "1", "Smoke test only in this configuration")
    }

    @MainActor func testGalleryLight() { gallery(scheme: "light") }
    @MainActor func testGalleryDark() { gallery(scheme: "dark") }

    @MainActor
    private func gallery(scheme: String) {
        let app = XCUIApplication()
        app.launchEnvironment["KAKEIBO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KAKEIBO_NO_REFINER"] = "1"
        app.launchEnvironment["KAKEIBO_SHOW_TOKENS"] = "1"
        app.launchEnvironment["KAKEIBO_COLOR_SCHEME"] = scheme
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_JP"]
        app.launch()

        let environment = app.staticTexts["tokens.environment"]
        XCTAssertTrue(environment.waitForExistence(timeout: 5))
        XCTAssertTrue(environment.label.contains("Appearance: \(scheme)"), environment.label)
        for page in 1...5 {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "gallery-\(scheme)-\(page)"
            shot.lifetime = .keepAlways
            add(shot)
            app.swipeUp()
        }
    }
}
