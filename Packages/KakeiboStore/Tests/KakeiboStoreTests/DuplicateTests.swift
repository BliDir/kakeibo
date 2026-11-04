import Foundation
import KakeiboCore
import SwiftData
import Testing
@testable import KakeiboStore

@MainActor
@Suite struct PossibleDuplicateTests {
    let container: ModelContainer
    let repo: ExpenseRepository

    init() throws {
        container = try KakeiboStore.makeContainer(inMemory: true)
        repo = ExpenseRepository(container: container)
    }

    static func draft(
        store: String? = "ローソン 中野坂上店",
        day: String = "2026-11-03",
        time: String? = "07:52",
        total: Int = 378,
        invoice: String? = "T6666666666666",
        receipt: String? = "1/2345"
    ) -> ReceiptDraft {
        ReceiptDraft(storeName: store, dayKey: day, time: time, totalYen: total, payment: .icCard,
                     category: .groceries, invoiceNumber: invoice, receiptNumber: receipt)
    }

    private func matches(_ draft: ReceiptDraft, excluding id: UUID? = nil) throws -> [ExpenseRepository.PossibleDuplicate.Strength] {
        try repo.possibleDuplicates(of: draft, excluding: id).map(\.strength)
    }

    // MARK: Strong

    @Test func sameReceiptNumberStoreAndDayIsStrong() throws {
        let saved = try repo.create(from: Self.draft(), source: .scan)
        let result = try repo.possibleDuplicates(of: Self.draft())
        #expect(result.map(\.strength) == [.strong])
        #expect(result.first?.expense.id == saved.id)
    }

    @Test func strongMatchIgnoresLeadingZerosAndOtherFields() throws {
        try repo.create(from: Self.draft(receipt: "01/2345"), source: .scan)
        // Total misread on one scan: the receipt number still says it is the same receipt.
        #expect(try matches(Self.draft(time: "07:53", total: 878, receipt: "1/02345")) == [.strong])
    }

    @Test func sameReceiptNumberAtAnotherStoreIsNotAMatch() throws {
        try repo.create(from: Self.draft(), source: .scan)
        #expect(try matches(Self.draft(store: "ファミリーマート", time: "12:00", total: 500, invoice: "T2468024680246")).isEmpty)
    }

    @Test func sameReceiptNumberOnAnotherDayIsNotAMatch() throws {
        try repo.create(from: Self.draft(), source: .scan)
        #expect(try matches(Self.draft(day: "2026-11-04")).isEmpty)
    }

    // MARK: Likely

    @Test func sameStoreDayTotalAndTimeIsLikely() throws {
        try repo.create(from: Self.draft(receipt: nil), source: .scan)
        #expect(try matches(Self.draft(receipt: nil)) == [.likely])
    }

    @Test func missingTimeOnEitherSideStillMatches() throws {
        try repo.create(from: Self.draft(time: nil, receipt: nil), source: .scan)
        #expect(try matches(Self.draft(receipt: nil)) == [.likely])
        #expect(try matches(Self.draft(time: nil, receipt: nil)) == [.likely])
    }

    @Test func sameStoreDifferentTotalIsNotAMatch() throws {
        try repo.create(from: Self.draft(receipt: nil), source: .scan)
        #expect(try matches(Self.draft(total: 520, receipt: nil)).isEmpty)
    }

    @Test func sameStoreDifferentTimeIsNotAMatch() throws {
        // A second coffee at the same shop later the same day.
        try repo.create(from: Self.draft(receipt: nil), source: .scan)
        #expect(try matches(Self.draft(time: "15:10", receipt: nil)).isEmpty)
    }

    // MARK: Store identity

    @Test func invoiceNumberAloneIsNotEnough() throws {
        // Same shop (same 登録番号), same day, different visit.
        try repo.create(from: Self.draft(), source: .scan)
        #expect(try matches(Self.draft(time: "18:30", total: 640, receipt: "1/2399")).isEmpty)
    }

    @Test func invoiceNumberDecidesTheStoreWhenBothHaveOne() throws {
        // OCR read the store name differently, but the invoice number says it is the same shop.
        try repo.create(from: Self.draft(store: "ローソン中野坂上店", receipt: nil), source: .scan)
        #expect(try matches(Self.draft(store: "LAWSON", receipt: nil)) == [.likely])
        // Same chain name, different franchise owner: not the same store.
        #expect(try matches(Self.draft(store: "ローソン中野坂上店", invoice: "T1111111111111", receipt: nil)).isEmpty)
    }

    @Test func storeNameIsComparedNormalizedWhenAnInvoiceNumberIsMissing() throws {
        try repo.create(from: Self.draft(store: "ＤＡＩＳＯ 中野店", invoice: nil, receipt: nil), source: .scan)
        #expect(try matches(Self.draft(store: "DAISO  中野店", receipt: nil)) == [.likely])
        #expect(try matches(Self.draft(store: "DAISO 新宿店", receipt: nil)).isEmpty)
    }

    @Test func emptyStoreNamesDoNotMatch() throws {
        try repo.create(from: Self.draft(store: nil, invoice: nil, receipt: nil), source: .manual)
        #expect(try matches(Self.draft(store: nil, invoice: nil, receipt: nil)).isEmpty)
    }

    // MARK: Ordering and self-exclusion

    @Test func strongMatchesComeFirst() throws {
        try repo.create(from: Self.draft(receipt: nil), source: .scan)
        try repo.create(from: Self.draft(), source: .scan, now: .now.addingTimeInterval(-60))
        #expect(try matches(Self.draft()) == [.strong, .likely])
    }

    @Test func editingNeverMatchesItself() throws {
        let saved = try repo.create(from: Self.draft(), source: .scan)
        #expect(try matches(Self.draft(), excluding: saved.id).isEmpty)
        // But it still finds another copy.
        let copy = try repo.create(from: Self.draft(), source: .scan)
        #expect(try repo.possibleDuplicates(of: Self.draft(), excluding: saved.id).map(\.expense.id) == [copy.id])
    }

    @Test func createAndUpdateStoreTheReceiptNumber() throws {
        let saved = try repo.create(from: Self.draft(), source: .scan)
        #expect(saved.receiptNumber == "1/2345")
        try repo.update(saved, from: Self.draft(receipt: "1/2346"))
        #expect(saved.receiptNumber == "1/2346")
    }

    // MARK: Review form

    @Test func formChecksManualEntriesWithTheLikelyRule() throws {
        try repo.create(from: Self.draft(store: "ダイソー", time: nil, invoice: nil, receipt: nil), source: .manual)
        let form = ReviewForm(manualOn: Date(timeIntervalSince1970: 1_793_674_800)) // 2026-11-03
        form.draft.storeName = "ダイソー"
        form.draft.totalYen = 378
        #expect(try form.possibleDuplicates(repository: repo).map(\.strength) == [.likely])
        form.draft.totalYen = 660
        #expect(try form.possibleDuplicates(repository: repo).isEmpty)
    }

    @Test func formChecksScans() throws {
        try repo.create(from: Self.draft(), source: .scan)
        let form = ReviewForm(scan: Self.draft(), ocrText: "", photo: nil, refining: false)
        #expect(try form.possibleDuplicates(repository: repo).map(\.strength) == [.strong])
    }

    @Test func formEditingDoesNotMatchItsOwnExpense() throws {
        let saved = try repo.create(from: Self.draft(), source: .scan)
        let form = ReviewForm(editing: saved)
        #expect(form.draft.receiptNumber == "1/2345")
        #expect(try form.possibleDuplicates(repository: repo).isEmpty)
    }

    @Test func formWithoutADateFindsNothing() throws {
        try repo.create(from: Self.draft(), source: .scan)
        var draft = Self.draft()
        draft.dayKey = nil
        let form = ReviewForm(scan: draft, ocrText: "", photo: nil, refining: false)
        #expect(try form.possibleDuplicates(repository: repo).isEmpty)
    }
}
