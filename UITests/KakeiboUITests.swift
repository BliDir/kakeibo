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
        XCTAssertTrue(app.staticTexts["Saved 754 yen"].waitForExistence(timeout: 5), "save confirmation")
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
        XCTAssertTrue(app.staticTexts["Saved 880 yen"].waitForExistence(timeout: 5))

        // Edit: change the amount.
        let row = app.buttons["ledger.row"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["Edit expense"].waitForExistence(timeout: 3))
        XCTAssertEqual(amount.value as? String, "880")
        amount.tap()
        amount.typeText("0")
        app.buttons["review.save"].tap()
        XCTAssertTrue(app.staticTexts["Saved 8,800 yen"].waitForExistence(timeout: 5))

        // Delete with the in-app confirmation.
        row.tap()
        let delete = scrollTo(app.buttons["review.delete"], in: app)
        delete.tap()
        XCTAssertTrue(app.staticTexts["Delete this expense?"].waitForExistence(timeout: 2))
        app.buttons["confirm.action"].tap()
        XCTAssertTrue(app.staticTexts["Expense deleted"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ledger.row"].exists)
    }

    // MARK: Summary

    /// The Summary tab shows the month by category, largest first, and follows the ledger's month.
    @MainActor
    func testSummaryShowsCategoriesAndFollowsTheMonth() {
        let app = launch(seed: true)
        app.tabBars.buttons["Summary"].tap()
        let total = app.staticTexts["summary.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertEqual(total.label, "5,198 yen")
        XCTAssertEqual(app.staticTexts["summary.count"].label, "4 receipts")

        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'summary.category.'"))
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.element(boundBy: 0).identifier, "summary.category.transport", "largest first")
        XCTAssertEqual(rows.element(boundBy: 3).identifier, "summary.category.household")
        // VoiceOver: both names, the amount and the share.
        let transport = app.descendants(matching: .any)["summary.category.transport"]
        XCTAssertEqual(transport.label, "Transport, 交通")
        XCTAssertEqual(transport.value as? String, "2,150 yen, 41.4%")

        let comparison = app.descendants(matching: .any)["summary.comparison"]
        XCTAssertTrue(comparison.exists)
        XCTAssertTrue(comparison.label.hasPrefix("1,920 yen more than"), comparison.label)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "summary"
        shot.lifetime = .keepAlways
        add(shot)

        // Last month: one category.
        app.buttons["summary.previous"].tap()
        XCTAssertEqual(total.label, "3,278 yen")
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(app.descendants(matching: .any)["summary.category.kids"].exists)

        // The ledger shows the same month.
        app.tabBars.buttons["Ledger"].tap()
        XCTAssertEqual(app.staticTexts["ledger.total"].label, "3,278 yen")
    }

    /// A saved entry shows up in the summary straight away.
    @MainActor
    func testSummaryUpdatesAfterSaving() {
        let app = launch()
        app.tabBars.buttons["Summary"].tap()
        XCTAssertTrue(app.staticTexts["summary.empty"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["summary.total"].label, "0 yen")

        app.tabBars.buttons["Ledger"].tap()
        addManualExpense(app, amount: "880", store: "Cafe Poem")
        XCTAssertTrue(app.staticTexts["Saved 880 yen"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Summary"].tap()
        XCTAssertEqual(app.staticTexts["summary.total"].label, "880 yen")
        XCTAssertFalse(app.staticTexts["summary.empty"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["summary.category.other"].exists)
    }

    // MARK: Settings

    /// Settings shows the language, privacy note, photo storage and version, and has no account.
    @MainActor
    func testSettingsShowsPrivacyStorageAndVersion() {
        let app = launch()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Everything stays on this iPhone"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.language"].exists)
        XCTAssertTrue(app.buttons["settings.language"].label.contains("System · English"), app.buttons["settings.language"].label)

        let photos = app.descendants(matching: .any)["settings.photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 3))
        XCTAssertTrue(photos.label.hasPrefix("0 photos, "), photos.label)

        let version = app.staticTexts["settings.version"].label
        XCTAssertNotNil(version.range(of: #"^\d+(\.\d+)* \(\d+\)$"#, options: .regularExpression), version)

        for word in ["Sign in", "Log in", "Account"] {
            XCTAssertFalse(app.staticTexts[word].exists, "no \(word) in v1.0")
            XCTAssertFalse(app.buttons[word].exists, "no \(word) in v1.0")
        }

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "settings"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The default payment from Settings is what a new manual entry starts with.
    @MainActor
    func testDefaultPaymentAppliesToManualEntries() {
        let app = launch()
        app.tabBars.buttons["Settings"].tap()
        let picker = app.buttons["settings.payment"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let icCard = app.buttons["IC card · 交通系IC"]
        XCTAssertTrue(icCard.waitForExistence(timeout: 3))
        icCard.tap()

        app.tabBars.buttons["Ledger"].tap()
        app.buttons["ledger.add"].tap()
        let payment = app.buttons["review.payment"]
        XCTAssertTrue(payment.waitForExistence(timeout: 3))
        XCTAssertTrue(payment.label.contains("IC card"), payment.label)
    }

    /// A scan's photo counts in Settings' storage.
    @MainActor
    func testSavedScanPhotoCountsInStorage() {
        let app = launch(scan: true)
        XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 30))
        app.buttons["review.save"].tap()
        XCTAssertTrue(app.staticTexts["Saved 754 yen"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        let photos = app.descendants(matching: .any)["settings.photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 5))
        XCTAssertTrue(photos.label.hasPrefix("1 photo, "), photos.label)
    }

    // MARK: Duplicates

    /// Saving the same entry twice warns first; Cancel keeps the form, Save anyway saves.
    @MainActor
    func testSavingTheSameEntryTwiceWarns() {
        let app = launch()
        addManualExpense(app, amount: "880", store: "Cafe Poem")
        XCTAssertTrue(app.staticTexts["Saved 880 yen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Already saved?"].exists, "first save has nothing to match")

        addManualExpense(app, amount: "880", store: "Cafe Poem")
        XCTAssertTrue(app.staticTexts["Already saved?"].waitForExistence(timeout: 3))
        let entry = app.descendants(matching: .any)["duplicate.entry"].firstMatch
        XCTAssertTrue(entry.exists)
        XCTAssertTrue(entry.label.contains("Cafe Poem"), entry.label)
        XCTAssertTrue(entry.label.contains("880 yen"), entry.label)
        XCTAssertTrue(app.buttons["duplicate.view"].exists)

        app.buttons["duplicate.cancel"].tap()
        XCTAssertFalse(app.staticTexts["Already saved?"].exists)
        XCTAssertTrue(app.staticTexts["Add expense"].exists, "Cancel stays on the form")

        app.buttons["review.save"].tap()
        XCTAssertTrue(app.buttons["duplicate.saveAnyway"].waitForExistence(timeout: 3))
        app.buttons["duplicate.saveAnyway"].tap()
        XCTAssertTrue(app.staticTexts["Saved 880 yen"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "ledger.row").count, 2)
    }

    /// "View saved entry" drops the new entry and opens the saved one.
    @MainActor
    func testDuplicateWarningOpensTheSavedEntry() {
        let app = launch()
        addManualExpense(app, amount: "1200", store: "Bento Ya")
        XCTAssertTrue(app.staticTexts["Saved 1,200 yen"].waitForExistence(timeout: 5))

        addManualExpense(app, amount: "1200", store: "Bento Ya")
        XCTAssertTrue(app.buttons["duplicate.view"].waitForExistence(timeout: 3))
        app.buttons["duplicate.view"].tap()
        XCTAssertTrue(app.staticTexts["Edit expense"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["review.amount"].value as? String, "1200")

        // Saving the saved entry unchanged does not warn about itself.
        app.buttons["review.cancel"].tap()
        XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons.matching(identifier: "ledger.row").count, 1, "the second entry was not saved")
    }

    /// A different amount at the same store is a second purchase, not a duplicate.
    @MainActor
    func testSameStoreDifferentAmountDoesNotWarn() {
        let app = launch()
        addManualExpense(app, amount: "880", store: "Cafe Poem")
        XCTAssertTrue(app.staticTexts["Saved 880 yen"].waitForExistence(timeout: 5))
        addManualExpense(app, amount: "450", store: "Cafe Poem")
        XCTAssertTrue(app.staticTexts["Saved 450 yen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Already saved?"].exists)
    }

    @MainActor
    private func addManualExpense(_ app: XCUIApplication, amount: String, store: String) {
        let add = app.buttons["ledger.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let amountField = app.textFields["review.amount"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 3))
        amountField.tap()
        amountField.typeText(amount)
        let storeField = app.textFields["review.store"]
        storeField.tap()
        storeField.typeText(store)
        app.buttons["review.save"].tap()
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

    // MARK: Ledger

    @MainActor
    func testEmptyLedgerExplainsHowToStart() {
        let app = launch()
        XCTAssertTrue(app.otherElements["ledger.empty"].waitForExistence(timeout: 5)
                      || app.staticTexts["No receipts for this month"].waitForExistence(timeout: 1))
        XCTAssertEqual(app.staticTexts["ledger.total"].label, "0 yen")
        XCTAssertFalse(app.buttons["ledger.next"].isEnabled, "no future months")
    }

    @MainActor
    func testLedgerShowsMonthTotalsAndSwitchesMonths() {
        let app = launch(seed: true)
        let total = app.staticTexts["ledger.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertEqual(total.label, "5,198 yen")
        XCTAssertEqual(app.staticTexts["ledger.count"].label, "4 receipts")
        XCTAssertEqual(app.buttons.matching(identifier: "ledger.row").count, 4)
        XCTAssertFalse(app.buttons["ledger.next"].isEnabled)

        app.buttons["ledger.previous"].tap()
        XCTAssertEqual(total.label, "3,278 yen")
        XCTAssertEqual(app.staticTexts["ledger.count"].label, "1 receipt")
        XCTAssertTrue(app.buttons["ledger.next"].isEnabled)

        app.buttons["ledger.next"].tap()
        XCTAssertEqual(total.label, "5,198 yen")
    }

    @MainActor
    func testLedgerUpdatesAfterEditAndDelete() {
        let app = launch(seed: true)
        let total = app.staticTexts["ledger.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        let row = app.buttons.matching(identifier: "ledger.row").firstMatch
        XCTAssertTrue(row.label.contains("1,078 yen"))          // newest first: Starbucks
        // VoiceOver reads the row as one element: store, category, payment, amount, date.
        XCTAssertTrue(row.label.hasPrefix("スターバックス, Starbucks, Dining out, Credit card, 1,078 yen, "), row.label)
        row.tap()
        let delete = scrollTo(app.buttons["review.delete"], in: app)
        delete.tap()
        app.buttons["confirm.action"].tap()
        XCTAssertTrue(app.staticTexts["Expense deleted"].waitForExistence(timeout: 5))
        XCTAssertEqual(total.label, "4,120 yen")
        XCTAssertEqual(app.buttons.matching(identifier: "ledger.row").count, 3)
    }

    // MARK: Export

    @MainActor
    func testExportOffersMonthAndYearFiles() {
        let app = launch(seed: true)
        app.buttons["ledger.export"].tap()
        XCTAssertTrue(app.buttons["export.month"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["export.year"].exists)
        // The seed data is dated relative to today, so match the file name's shape, not a date.
        let monthFile = NSPredicate(format: "label MATCHES 'kakeibo-[0-9]{4}-[0-9]{2}\\.csv · 4 receipts'")
        XCTAssertEqual(app.staticTexts.matching(monthFile).count, 1)
        app.buttons["export.close"].tap()
        XCTAssertTrue(app.buttons["ledger.export"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testExportOfAnEmptyMonthHasNothingToShare() {
        let app = launch()
        app.buttons["ledger.export"].tap()
        XCTAssertTrue(app.staticTexts["Nothing to export"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["export.month"].exists)
    }

    // MARK: Debug fixture capture

    @MainActor
    func testSaveAsFixtureOffersTextJSONAndImage() {
        let app = launch(scan: true)
        XCTAssertTrue(app.textFields["review.amount"].waitForExistence(timeout: 30))
        app.buttons["review.fixture"].tap()
        XCTAssertTrue(app.buttons["fixture.share"].waitForExistence(timeout: 5))
        let names = app.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(names.contains { $0.hasPrefix("real-") && $0.hasSuffix(".txt") })
        XCTAssertTrue(names.contains { $0.hasPrefix("real-") && $0.hasSuffix(".expected.json") })
        XCTAssertTrue(names.contains { $0.hasPrefix("real-") && $0.hasSuffix(".jpg") })
    }

    @MainActor
    func testManualEntryHasNoFixtureButton() {
        let app = launch()
        app.buttons["ledger.add"].tap()
        XCTAssertTrue(app.buttons["review.cancel"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["review.fixture"].exists)
    }

    // MARK: Helpers

    /// Launches with an empty in-memory ledger in English, without the on-device model.
    /// With `scan`, a scan of the bundled made-up receipt starts at once; with `seed`, the ledger
    /// starts with four made-up expenses this month and one last month.
    @MainActor
    private func launch(scan: Bool = false, ocrDelay: Double? = nil, seed: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KAKEIBO_IN_MEMORY_STORE"] = "1"
        if seed { app.launchEnvironment["KAKEIBO_SEED_SAMPLE"] = "1" }
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
