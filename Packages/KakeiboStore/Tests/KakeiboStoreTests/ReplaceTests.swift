import Foundation
import KakeiboCore
import SwiftData
import Testing
@testable import KakeiboStore

/// B-16: "Replace saved entry" on the duplicate warning updates the saved expense in place.
@MainActor
@Suite struct ReplaceTests {
    struct SaveFailed: Error {}

    let temp: TempPhotoStore
    let repo: ExpenseRepository
    static let created = Date(timeIntervalSince1970: 1_793_674_800)   // 2026-11-03 12:00 Tokyo
    static let later = created.addingTimeInterval(3_600)

    init() throws {
        temp = try TempPhotoStore()
        repo = ExpenseRepository(container: try KakeiboStore.makeContainer(inMemory: true), photoStore: temp.store)
    }

    /// The first, poor scan: wrong total and items.
    static func firstScan() -> ReceiptDraft {
        ReceiptDraft(storeName: "ファミリーマート", dayKey: "2026-11-07", time: "18:00", totalYen: 1_299,
                     tax8Yen: 96, payment: .credit, category: .groceries, invoiceNumber: "T4011601002009",
                     receiptNumber: "2-5138",
                     items: [LineItemDraft(name: "ニーニニニ", priceYen: 170), LineItemDraft(name: "大きいウインナー", priceYen: 150)],
                     confidences: [.storeName: .high, .dayKey: .high, .totalYen: .low])
    }

    /// The rescan: right total and items.
    static func rescan() -> ReceiptDraft {
        ReceiptDraft(storeName: "ファミリーマート", dayKey: "2026-11-07", time: "18:00", totalYen: 1_469,
                     tax10Yen: 0, tax8Yen: 108, payment: .credit, category: .groceries, invoiceNumber: "T4011601002009",
                     receiptNumber: "2-5138",
                     items: [LineItemDraft(name: "大きいウインナー", priceYen: 170, isReducedRate: true),
                             LineItemDraft(name: "和風ツナパン", priceYen: 150, isReducedRate: true)],
                     confidences: [.storeName: .high, .dayKey: .high, .totalYen: .high])
    }

    /// A saved first scan with a photo and a note.
    private func savedScan(note: String = "夕食") throws -> Expense {
        let photo = try temp.store.save(imageData: TestImages.data())
        return try repo.create(from: Self.firstScan(), source: .scan, note: note, ocrText: "old text",
                               photoFileName: photo, now: Self.created)
    }

    private func rescanForm(photo: Bool = true) -> ReviewForm {
        ReviewForm(scan: Self.rescan(), ocrText: "new text", photo: photo ? .data(TestImages.data()) : nil, refining: false)
    }

    // MARK: Repository

    @Test func replaceKeepsTheEntryAndTakesTheNewScan() throws {
        let saved = try savedScan()
        let id = saved.id
        try repo.replace(saved, from: Self.rescan(), source: .scan, ocrText: "new text", photoFileName: nil, now: Self.later)

        let all = try repo.expenses(inMonth: "2026-11")
        #expect(all.count == 1)
        let expense = try #require(all.first)
        #expect(expense.id == id)
        #expect(expense.createdAt == Self.created)
        #expect(expense.updatedAt == Self.later)
        #expect(expense.totalYen == 1_469)
        #expect(expense.tax8Yen == 108)
        #expect(expense.tax10Yen == 0)
        #expect(expense.orderedItems.map(\.priceYen) == [170, 150])
        #expect(expense.orderedItems.allSatisfy { $0.isReducedRate })
        #expect(expense.ocrText == "new text")
        #expect(expense.confidence == .high)
        #expect(expense.note == "夕食", "an empty new note keeps the saved one")
        #expect(try repo.context.fetch(FetchDescriptor<LineItem>()).count == 2, "old items are gone")
    }

    @Test func aNewNoteReplacesTheOldOne() throws {
        let saved = try savedScan()
        try repo.replace(saved, from: Self.rescan(), source: .scan, note: "レシート再読込", now: Self.later)
        #expect(saved.note == "レシート再読込")
    }

    @Test func confidenceComesFromTheNewScan() throws {
        let saved = try repo.create(from: Self.rescan(), source: .scan, now: Self.created)
        #expect(saved.confidence == .high)
        try repo.replace(saved, from: Self.firstScan(), source: .scan, now: Self.later)
        #expect(saved.confidence == .low)
    }

    // MARK: Photos

    @Test func newPhotoReplacesTheOldFile() async throws {
        let saved = try savedScan()
        let oldPhoto = try #require(saved.photoFileName)
        try await rescanForm().replace(saved, repository: repo, photoStore: temp.store, now: Self.later)

        let newPhoto = try #require(saved.photoFileName)
        #expect(newPhoto != oldPhoto)
        #expect(try temp.store.storedNames() == [newPhoto], "the old file is deleted")
        #expect(saved.ocrText == "new text")
        #expect(saved.source == .scan)
    }

    @Test func failedReplaceKeepsTheOldEntryAndPhoto() async throws {
        let saved = try savedScan()
        let oldPhoto = try #require(saved.photoFileName)
        repo.beforeSave = { throw SaveFailed() }
        await #expect(throws: SaveFailed.self) {
            try await rescanForm().replace(saved, repository: repo, photoStore: temp.store, now: Self.later)
        }
        repo.beforeSave = nil

        let expense = try #require(try repo.expense(id: saved.id))
        #expect(expense.totalYen == 1_299)
        #expect(expense.orderedItems.map(\.priceYen) == [170, 150])
        #expect(expense.photoFileName == oldPhoto)
        #expect(expense.ocrText == "old text")
        #expect(expense.updatedAt == Self.created)
        #expect(try temp.store.storedNames() == [oldPhoto], "the new file is removed, the old one kept")
    }

    @Test func manualReplaceKeepsThePhoto() async throws {
        let saved = try savedScan()
        let oldPhoto = try #require(saved.photoFileName)
        let form = ReviewForm(manualOn: Self.created, payment: .cash)
        form.draft = Self.rescan()
        try await form.replace(saved, repository: repo, photoStore: temp.store, now: Self.later)

        #expect(saved.totalYen == 1_469)
        #expect(saved.photoFileName == oldPhoto)
        #expect(saved.ocrText == "old text", "the text that belongs to the kept photo stays")
        #expect(saved.source == .scan)
        #expect(saved.confidence == .high)
        #expect(saved.note == "夕食")
        #expect(try temp.store.storedNames() == [oldPhoto])
    }

    @Test func onlyNewEntriesCanReplace() throws {
        #expect(rescanForm().canReplace)
        #expect(ReviewForm(manualOn: Self.created).canReplace)
        #expect(!ReviewForm(editing: try savedScan()).canReplace)
    }

    @Test func invalidDraftChangesNothing() async throws {
        let saved = try savedScan()
        var bad = Self.rescan()
        bad.totalYen = nil
        #expect(throws: ExpenseRepository.Error.missingTotal) {
            try repo.replace(saved, from: bad, source: .scan, now: Self.later)
        }
        #expect(saved.totalYen == 1_299)
    }
}

/// B-16: a replace is one committed edit for budget alerts.
@MainActor
@Suite struct ReplaceAlertTests {
    @Test func replaceEvaluatesOnceWithoutARepeatAlert() async throws {
        let now = Calendar.kakeibo.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
        let container = try KakeiboStore.makeContainer(inMemory: true)
        let expenses = ExpenseRepository(container: container)
        let budgets = BudgetRepository(container: container)
        let center = InMemoryNotificationCenter(status: .allowed)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "ReplaceAlertTests-\(UUID().uuidString)")!)
        settings.budgetAlertsEnabled = true
        let notifier = BudgetNotifier(center: center, settings: settings) { _ in BudgetNotificationCopy(title: "t", body: "b") }
        let coordinator = BudgetAlertCoordinator(expenses: expenses, budgets: budgets, notifier: notifier, now: { now })
        func settle() async {
            for _ in 0..<2 {
                for _ in 0..<5 { await Task.yield() }
                await coordinator.waitUntilIdle()
            }
        }
        let november = LedgerMonth(year: 2026, month: 11)
        try budgets.setBudget(2_000, for: november, now: now)
        // First scan: ¥1,700 of ¥2,000 is 85% → the 80% alert.
        let saved = try expenses.create(from: ReceiptDraft(storeName: "店", dayKey: "2026-11-10", totalYen: 1_700),
                                        source: .scan, now: now)
        await settle()
        #expect(await center.added == ["budget-2026-11-80"])

        // The rescan reads ¥1,750: still one entry, still 80%, no second alert.
        try expenses.replace(saved, from: ReceiptDraft(storeName: "店", dayKey: "2026-11-10", totalYen: 1_750),
                             source: .scan, now: now)
        await settle()
        #expect(try expenses.expenses(inMonth: "2026-11").count == 1)
        #expect(MonthSpend.total(try expenses.expenses(inMonth: "2026-11")) == 1_750)
        #expect(await center.added == ["budget-2026-11-80"])

        // A rescan that reads ¥2,100 crosses 100% once, as any edit would.
        try expenses.replace(saved, from: ReceiptDraft(storeName: "店", dayKey: "2026-11-10", totalYen: 2_100),
                             source: .scan, now: now)
        await settle()
        #expect(await center.added == ["budget-2026-11-80", "budget-2026-11-100"])
    }
}
