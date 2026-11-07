import XCTest

/// The real photo path with no debug scan hooks (UI-07): the native PhotosPicker, reading,
/// review, save, the details with the original receipt, edit and delete.
///
/// Opt-in, because it needs the sample receipt in the simulator's photo library and drives
/// the system picker (newest photo first):
///
///     xcrun simctl addmedia "iPhone 17" UITests/sample-receipt.png
///     TEST_RUNNER_KAKEIBO_PICKER_PROBE=1 xcodebuild test -scheme Kakeibo \
///       -destination 'platform=iOS Simulator,name=iPhone 17' -only-test-configuration English \
///       -only-testing:KakeiboUITests/NativePhotoPickerTests
final class NativePhotoPickerTests: XCTestCase {
    @MainActor
    func testRealPhotoPickerFlow() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KAKEIBO_PICKER_PROBE"] == "1",
                          "Set TEST_RUNNER_KAKEIBO_PICKER_PROBE=1 (and add the sample receipt to Photos) to run it")
        let app = XCUIApplication()
        app.launchEnvironment["KAKEIBO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KAKEIBO_NO_REFINER"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_JP"]
        app.launch()
        func shot(_ name: String) {
            let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        }
        XCTAssertTrue(app.buttons["scan.photo"].waitForExistence(timeout: 10))
        app.buttons["scan.photo"].tap()
        let image = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 10), "photo grid in the native picker")
        shot("picker-1-native-picker")
        // The picker is a remote view: its cells are not "hittable", so tap the cell's centre.
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let amount = app.textFields["review.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 40), "review after picking a photo")
        shot("picker-2-review")
        app.buttons["review.save"].tap()
        XCTAssertTrue(app.buttons["ledger.row"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["ledger.row"].label.contains("754 yen"), app.buttons["ledger.row"].label)
        shot("picker-3-saved")
        app.buttons["ledger.row"].tap()
        XCTAssertTrue(app.buttons["detail.photo"].waitForExistence(timeout: 5))
        app.buttons["detail.photo"].tap()
        XCTAssertTrue(app.buttons["photo.close"].waitForExistence(timeout: 5))
        shot("picker-4-original-receipt")
        app.buttons["photo.close"].tap()
        app.buttons["detail.edit"].tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        app.buttons["review.cancel"].tap()
        app.buttons["detail.delete"].tap()
        app.buttons["confirm.action"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ledger.empty"].firstMatch.waitForExistence(timeout: 5))
        shot("picker-5-deleted")
    }
}
