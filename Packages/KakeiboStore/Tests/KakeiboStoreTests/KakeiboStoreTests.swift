import Foundation
import KakeiboCore
import SwiftData
import Testing
@testable import KakeiboStore

@MainActor
@Suite struct ExpenseRepositoryTests {
    let container: ModelContainer
    let repo: ExpenseRepository

    init() throws {
        container = try KakeiboStore.makeContainer(inMemory: true)
        repo = ExpenseRepository(container: container)
    }

    static let now = Date(timeIntervalSince1970: 1_793_674_800)

    static func draft(
        day: String = "2026-11-03",
        total: Int = 658,
        store: String = "セブン-イレブン",
        items: [LineItemDraft] = []
    ) -> ReceiptDraft {
        ReceiptDraft(
            storeName: store,
            storeNameEn: "7-Eleven",
            dayKey: day,
            time: "08:15",
            totalYen: total,
            tax10Yen: 18,
            tax8Yen: 33,
            payment: .icCard,
            category: .groceries,
            invoiceNumber: "T1234567890123",
            items: items,
            confidences: [.storeName: .high, .dayKey: .high, .totalYen: .medium]
        )
    }

    private func allExpenses() throws -> [Expense] { try container.mainContext.fetch(FetchDescriptor<Expense>()) }
    private func allItems() throws -> [LineItem] { try container.mainContext.fetch(FetchDescriptor<LineItem>()) }

    // MARK: Create

    @Test func createCopiesEveryField() throws {
        let items = [
            LineItemDraft(name: "おにぎり", nameEn: "Rice ball", priceYen: 160, isReducedRate: true),
            LineItemDraft(name: "コーヒー", priceYen: 200),
            LineItemDraft(name: "値引", priceYen: -30, isReducedRate: true),
        ]
        let e = try repo.create(from: Self.draft(items: items), source: .scan, note: "朝ごはん",
                                ocrText: "合計 ¥658", photoFileName: "abc.jpg", now: Self.now)

        #expect(e.dayKey == "2026-11-03")
        #expect(e.time == "08:15")
        #expect(e.storeName == "セブン-イレブン")
        #expect(e.storeNameEn == "7-Eleven")
        #expect(e.totalYen == 658)
        #expect(e.tax10Yen == 18)
        #expect(e.tax8Yen == 33)
        #expect(e.payment == .icCard)
        #expect(e.category == .groceries)
        #expect(e.invoiceNumber == "T1234567890123")
        #expect(e.note == "朝ごはん")
        #expect(e.ocrText == "合計 ¥658")
        #expect(e.photoFileName == "abc.jpg")
        #expect(e.source == .scan)
        #expect(e.confidence == .medium)  // lowest of store, date and total
        #expect(e.createdAt == Self.now)
        #expect(e.updatedAt == Self.now)

        #expect(e.orderedItems.map(\.name) == ["おにぎり", "コーヒー", "値引"])
        #expect(e.orderedItems.map(\.priceYen) == [160, 200, -30])
        #expect(e.orderedItems[0].nameEn == "Rice ball")
        #expect(e.orderedItems[0].isReducedRate)
        #expect(e.orderedItems.allSatisfy { $0.expense === e })
        #expect(try allExpenses().count == 1)
    }

    @Test func storedRawValuesAreStable() throws {
        let e = try repo.create(from: Self.draft(), source: .scan, now: Self.now)
        #expect(e.paymentRaw == "icCard")
        #expect(e.categoryRaw == "groceries")
        #expect(e.sourceRaw == "scan")
        #expect(e.confidenceRaw == "medium")
    }

    @Test func manualEntryIsHighConfidenceWithDefaults() throws {
        let draft = ReceiptDraft(dayKey: "2026-11-03", totalYen: 500)
        let e = try repo.create(from: draft, source: .manual, now: Self.now)
        #expect(e.confidence == .high)
        #expect(e.storeName == "")
        #expect(e.payment == .cash)
        #expect(e.category == .other)
        #expect(e.items.isEmpty)
    }

    @Test func createRejectsIncompleteDrafts() {
        #expect(throws: ExpenseRepository.Error.missingDayKey) {
            try repo.create(from: ReceiptDraft(totalYen: 500), source: .manual)
        }
        #expect(throws: ExpenseRepository.Error.missingTotal) {
            try repo.create(from: ReceiptDraft(dayKey: "2026-11-03"), source: .manual)
        }
        for bad in ["2026-13-01", "2026-02-30", "2026/11/03", "2026-1-3", "26-11-03"] {
            #expect(throws: ExpenseRepository.Error.invalidDayKey(bad)) {
                try repo.create(from: ReceiptDraft(dayKey: bad, totalYen: 500), source: .manual)
            }
        }
    }

    // MARK: Update

    @Test func updateReplacesFieldsAndItems() throws {
        let created = Self.now
        let later = Self.now.addingTimeInterval(3600)
        let e = try repo.create(from: Self.draft(items: [LineItemDraft(name: "旧", priceYen: 100)]),
                                source: .scan, ocrText: "ocr", photoFileName: "p.jpg", now: created)

        var corrected = Self.draft(day: "2026-11-02", total: 700, store: "ローソン",
                                   items: [LineItemDraft(name: "新A", priceYen: 300), LineItemDraft(name: "新B", priceYen: 400)])
        corrected.payment = .cash
        corrected.category = .dining
        corrected.tax8Yen = nil
        try repo.update(e, from: corrected, note: "修正", now: later)

        #expect(e.dayKey == "2026-11-02")
        #expect(e.totalYen == 700)
        #expect(e.storeName == "ローソン")
        #expect(e.payment == .cash)
        #expect(e.category == .dining)
        #expect(e.tax8Yen == nil)
        #expect(e.note == "修正")
        #expect(e.orderedItems.map(\.name) == ["新A", "新B"])
        #expect(e.confidence == .high)
        // Kept from creation.
        #expect(e.source == .scan)
        #expect(e.ocrText == "ocr")
        #expect(e.photoFileName == "p.jpg")
        #expect(e.createdAt == created)
        #expect(e.updatedAt == later)
        // The old item is gone, not orphaned.
        #expect(try allItems().map(\.name).sorted() == ["新A", "新B"])
    }

    @Test func updateKeepsNoteWhenNotGiven() throws {
        let e = try repo.create(from: Self.draft(), source: .scan, note: "メモ", now: Self.now)
        try repo.update(e, from: Self.draft(total: 900), now: Self.now)
        #expect(e.note == "メモ")
    }

    @Test func updateWithClosure() throws {
        let e = try repo.create(from: Self.draft(), source: .scan, now: Self.now)
        let later = Self.now.addingTimeInterval(60)
        try repo.update(e, now: later) { $0.note = "追記"; $0.category = .household }
        #expect(e.note == "追記")
        #expect(e.category == .household)
        #expect(e.updatedAt == later)
        #expect(throws: ExpenseRepository.Error.invalidDayKey("bad")) {
            try repo.update(e) { $0.dayKey = "bad" }
        }
    }

    // MARK: Delete

    @Test func deleteCascadesToItems() throws {
        let keep = try repo.create(from: Self.draft(items: [LineItemDraft(name: "残る", priceYen: 1)]), source: .scan, now: Self.now)
        let gone = try repo.create(from: Self.draft(items: [LineItemDraft(name: "消える", priceYen: 1),
                                                            LineItemDraft(name: "消える2", priceYen: 2)]),
                                   source: .scan, now: Self.now)
        #expect(try allItems().count == 3)
        try repo.delete(gone)
        #expect(try allExpenses().map(\.id) == [keep.id])
        #expect(try allItems().map(\.name) == ["残る"])
    }

    // MARK: Fetch

    @Test func fetchByMonthAndYear() throws {
        for (day, total) in [("2026-10-31", 1), ("2026-11-01", 2), ("2026-11-30", 3), ("2026-12-01", 4),
                             ("2025-11-15", 5), ("2027-01-01", 6)] {
            try repo.create(from: Self.draft(day: day, total: total), source: .manual, now: Self.now)
        }
        #expect(try repo.expenses(inMonth: "2026-11").map(\.dayKey) == ["2026-11-30", "2026-11-01"])
        #expect(try repo.expenses(inMonth: "2026-10").map(\.totalYen) == [1])
        #expect(try repo.expenses(inMonth: "2026-09").isEmpty)
        #expect(try repo.expenses(inYear: 2026).map(\.dayKey) == ["2026-12-01", "2026-11-30", "2026-11-01", "2026-10-31"])
        #expect(try repo.expenses(inYear: 2025).map(\.totalYen) == [5])
    }

    @Test func sameDayNewestCreatedFirst() throws {
        let first = try repo.create(from: Self.draft(), source: .manual, now: Self.now)
        let second = try repo.create(from: Self.draft(), source: .manual, now: Self.now.addingTimeInterval(10))
        #expect(try repo.expenses(inMonth: "2026-11").map(\.id) == [second.id, first.id])
    }

    @Test func rejectsBadMonth() {
        for bad in ["2026-1", "2026-13", "2026/11", "202611", "2026-11-03"] {
            #expect(throws: ExpenseRepository.Error.invalidMonth(bad)) { try repo.expenses(inMonth: bad) }
        }
    }

    @Test func fetchById() throws {
        let e = try repo.create(from: Self.draft(), source: .manual, now: Self.now)
        #expect(try repo.expense(id: e.id)?.id == e.id)
        #expect(try repo.expense(id: UUID()) == nil)
    }
}

@MainActor
@Suite struct RepositoryLifetimeTests {
    @Test func repositoryKeepsItsContainerAlive() throws {
        // No other reference to the container: the repository must hold it.
        let repo = ExpenseRepository(container: try KakeiboStore.makeContainer(inMemory: true))
        try repo.create(from: ReceiptDraft(dayKey: "2026-11-03", totalYen: 500), source: .manual)
        #expect(try repo.expenses(inMonth: "2026-11").count == 1)
    }
}

@Suite struct SchemaTests {
    @Test func schemaVersionAndModels() {
        #expect(KakeiboSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(KakeiboSchemaV1.models.count == 2)
        #expect(KakeiboSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(KakeiboSchemaV2.models.count == 2)
        #expect(KakeiboMigrationPlan.schemas.count == 2)
        #expect(KakeiboMigrationPlan.stages.count == 1)
    }

    @Test func dayKeyIsIndexed() {
        let schema = Schema(versionedSchema: KakeiboStore.CurrentSchema.self)
        let entity = schema.entities.first { $0.name == "Expense" }
        #expect(entity?.indices.contains { $0.contains("dayKey") } == true)
    }

    @Test func photosDirectoryNameIsSet() {
        #expect(!KakeiboStore.photosDirectoryName.isEmpty)
    }
}
