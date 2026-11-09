import CoreGraphics
import Foundation
import KakeiboCore
import SwiftData
import Testing
@testable import KakeiboStore

@MainActor
@Suite struct ReviewFormTests {
    let temp: TempPhotoStore
    let repo: ExpenseRepository
    static let now = Date(timeIntervalSince1970: 1_793_674_800) // 2026-11-03 12:00 Tokyo

    init() throws {
        temp = try TempPhotoStore()
        repo = ExpenseRepository(container: try KakeiboStore.makeContainer(inMemory: true), photoStore: temp.store)
    }

    static func scanDraft() -> ReceiptDraft {
        ReceiptDraft(
            storeName: "まいばすけっと", dayKey: "2026-10-31", time: "18:42", totalYen: 1_310,
            tax10Yen: 29, tax8Yen: 72, payment: .icCard, category: .groceries, invoiceNumber: "T1234567890123",
            items: [LineItemDraft(name: "牛乳", priceYen: 248, isReducedRate: true)],
            confidences: [.totalYen: .high, .storeName: .low, .dayKey: .high, .payment: .high, .category: .high]
        )
    }

    private func scanForm(_ draft: ReceiptDraft = scanDraft(), photo: ReviewForm.PendingPhoto? = nil) -> ReviewForm {
        ReviewForm(scan: draft, ocrText: "合計 ¥1,310", photo: photo, refining: false)
    }

    // MARK: Fields to check

    @Test func lowConfidenceFieldsNeedChecking() {
        let form = scanForm()
        #expect(form.fieldsToCheck == [.storeName])
        #expect(form.needsCheck(.storeName))
        #expect(!form.needsCheck(.totalYen))
        #expect(form.isTotalVerified)
    }

    @Test func missingFieldsNeedChecking() {
        let form = scanForm(ReceiptDraft(totalYen: 500, confidences: [.totalYen: .medium]))
        #expect(form.fieldsToCheck == [.storeName, .dayKey, .payment, .category])
        #expect(!form.isTotalVerified)
    }

    @Test func editingAFieldClearsItsCheck() {
        let form = scanForm()
        form.draft.storeName = "まいばすけっと 東神奈川店"
        #expect(form.fieldsToCheck.isEmpty)
    }

    /// B-13: items that do not add up are a field to check until the user changes them.
    @Test func itemsThatDoNotAddUpNeedChecking() {
        var draft = Self.scanDraft()
        draft.confidences[.items] = .low
        let form = scanForm(draft)
        #expect(form.fieldsToCheck == [.storeName, .items])
        form.draft.items.append(LineItemDraft(name: "パン", priceYen: 158))
        #expect(!form.needsCheck(.items))
    }

    @Test func itemsWithoutAConfidenceAreNotChecked() {
        var draft = Self.scanDraft()
        draft.items = []
        draft.confidences[.items] = .low
        #expect(!scanForm(draft).needsCheck(.items))
        #expect(!scanForm().needsCheck(.items))
    }

    @Test func editingTheTotalDropsVerified() {
        let form = scanForm()
        form.amountText = "1300"
        #expect(!form.isTotalVerified)
    }

    @Test func manualAndEditHaveNothingToCheck() throws {
        #expect(ReviewForm(manualOn: Self.now).fieldsToCheck.isEmpty)
        let saved = try repo.create(from: Self.scanDraft(), source: .scan, now: Self.now)
        #expect(ReviewForm(editing: saved).fieldsToCheck.isEmpty)
    }

    // MARK: Editing helpers

    @Test func amountTextKeepsDigitsOnly() {
        let form = ReviewForm(manualOn: Self.now)
        form.amountText = "¥1,234"
        #expect(form.draft.totalYen == 1_234)
        #expect(form.amountText == "1234")
        form.amountText = ""
        #expect(form.draft.totalYen == nil)
        form.amountText = "12345678901234"
        #expect(form.draft.totalYen == 123_456_789)
    }

    @Test func dateBindingUsesTokyoDayKey() throws {
        let form = ReviewForm(manualOn: Self.now)
        #expect(form.draft.dayKey == "2026-11-03")
        let october = try #require(DayKey.date(from: "2026-10-01"))
        form.date = october
        #expect(form.draft.dayKey == "2026-10-01")
        form.date = nil
        #expect(form.draft.dayKey == nil)
    }

    // MARK: Validation

    @Test func saveNeedsAmountAndDate() {
        let form = ReviewForm(manualOn: Self.now)
        #expect(form.problems == [.missingAmount])
        form.amountText = "0"
        #expect(form.problems == [.missingAmount])
        form.amountText = "500"
        #expect(form.canSave)
        form.draft.dayKey = nil
        #expect(form.problems == [.missingDate])
        form.draft.dayKey = "2026-02-30"
        #expect(!form.canSave)
    }

    // MARK: Unsaved changes

    @Test func unsavedScanAlwaysAsksBeforeDiscarding() {
        #expect(scanForm().hasUnsavedChanges)
    }

    @Test func manualAndEditAskOnlyAfterChanges() throws {
        let manual = ReviewForm(manualOn: Self.now)
        #expect(!manual.hasUnsavedChanges)
        manual.note = "BBQ"
        #expect(manual.hasUnsavedChanges)

        let saved = try repo.create(from: Self.scanDraft(), source: .scan, note: "メモ", now: Self.now)
        let edit = ReviewForm(editing: saved)
        #expect(!edit.hasUnsavedChanges)
        edit.draft.category = .dining
        #expect(edit.hasUnsavedChanges)
    }

    // MARK: Save

    @Test func savingAScanStoresExpenseAndPhoto() async throws {
        let form = scanForm(photo: .data(TestImages.data()))
        form.note = "週末"
        let expense = try await form.save(repository: repo, photoStore: temp.store, now: Self.now)

        #expect(expense.source == .scan)
        #expect(expense.totalYen == 1_310)
        #expect(expense.note == "週末")
        #expect(expense.ocrText == "合計 ¥1,310")
        let photo = try #require(expense.photoFileName)
        #expect(try temp.store.storedNames() == [photo])
        #expect(try repo.expenses(inMonth: "2026-10").count == 1)
    }

    @Test func savingACameraScanStoresTheImage() async throws {
        let form = scanForm(photo: .image(TestImages.cgImage(width: 200, height: 300)))
        let expense = try await form.save(repository: repo, photoStore: temp.store, now: Self.now)
        #expect(try temp.store.image(for: try #require(expense.photoFileName))?.width == 200)
    }

    @Test func failedSaveLeavesNoOrphanPhoto() async throws {
        var draft = Self.scanDraft()
        draft.dayKey = nil                         // the repository rejects this
        let form = scanForm(draft, photo: .data(TestImages.data()))
        await #expect(throws: ExpenseRepository.Error.missingDayKey) {
            _ = try await form.save(repository: repo, photoStore: temp.store, now: Self.now)
        }
        #expect(try temp.store.storedNames().isEmpty)
    }

    @Test func savingManualEntry() async throws {
        let form = ReviewForm(manualOn: Self.now)
        form.amountText = "880"
        form.draft.storeName = "喫茶ポエム"
        form.draft.category = .dining
        let expense = try await form.save(repository: repo, photoStore: temp.store, now: Self.now)
        #expect(expense.source == .manual)
        #expect(expense.photoFileName == nil)
        #expect(expense.category == .dining)
        #expect(try temp.store.storedNames().isEmpty)
    }

    @Test func savingAnEditUpdatesTheSameExpense() async throws {
        let saved = try repo.create(from: Self.scanDraft(), source: .scan, now: Self.now)
        let form = ReviewForm(editing: saved)
        #expect(form.draft.totalYen == 1_310)
        #expect(form.draft.items.map(\.name) == ["牛乳"])
        form.amountText = "1400"
        form.note = "修正"
        let updated = try await form.save(repository: repo, photoStore: temp.store, now: Self.now)
        #expect(updated.id == saved.id)
        #expect(updated.totalYen == 1_400)
        #expect(updated.note == "修正")
        #expect(try repo.expenses(inMonth: "2026-10").count == 1)
    }

    // MARK: Delete

    @Test func deleteRemovesExpenseAndPhoto() throws {
        let photo = try temp.store.save(imageData: TestImages.data())
        let saved = try repo.create(from: Self.scanDraft(), source: .scan, photoFileName: photo, now: Self.now)
        let form = ReviewForm(editing: saved)
        #expect(form.storedPhotoName == photo)
        #expect(form.hasPhoto)
        try form.delete(repository: repo)
        #expect(try repo.expenses(inMonth: "2026-10").isEmpty)
        #expect(try temp.store.storedNames().isEmpty)
    }

    @Test func deleteDoesNothingForNewEntries() throws {
        try ReviewForm(manualOn: Self.now).delete(repository: repo)
        #expect(!ReviewForm(manualOn: Self.now).hasPhoto)
    }

    // MARK: Background refinement

    @Test func refinementFillsUntouchedFieldsAndKeepsEdits() {
        var parser = Self.scanDraft()
        parser.items = []
        let form = ReviewForm(scan: parser, ocrText: "", photo: nil, refining: true)
        #expect(form.isRefining)
        form.draft.payment = .qrPay                  // the user changes payment while the model runs

        var refined = parser
        refined.payment = .credit
        refined.items = [LineItemDraft(name: "牛乳", nameEn: "Milk", priceYen: 248, isReducedRate: true)]
        refined.confidences[.items] = .medium
        form.applyRefinement(refined)

        #expect(!form.isRefining)
        #expect(form.wasRefined)
        #expect(form.draft.payment == .qrPay)
        #expect(form.draft.items.first?.nameEn == "Milk")
    }

    @Test func endRefinementStopsTheIndicator() {
        let form = ReviewForm(scan: Self.scanDraft(), ocrText: "", photo: nil, refining: true)
        form.endRefinement()
        #expect(!form.isRefining)
        #expect(!form.wasRefined)
    }
}
