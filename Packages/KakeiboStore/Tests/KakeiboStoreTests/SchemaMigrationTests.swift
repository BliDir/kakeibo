import Foundation
import KakeiboCore
import SwiftData
import Testing
@testable import KakeiboStore

/// Opens a store written with schema V1 using the current schema and migration plan.
@Suite struct SchemaMigrationTests {
    @Test func v1StoreSurvivesMigrationToV2() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MigrationTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Kakeibo.store")
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_793_674_800)

        // Write with V1 only, as v1.0 of the app did.
        do {
            let schema = Schema(versionedSchema: KakeiboSchemaV1.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(container)
            let expense = KakeiboSchemaV1.Expense(
                id: id, dayKey: "2026-11-03", time: "07:52", storeName: "ローソン", storeNameEn: "Lawson",
                totalYen: 378, tax8Yen: 28, payment: .icCard, category: .groceries,
                invoiceNumber: "T6666666666666", note: "朝ごはん", photoFileName: "\(id).jpg", ocrText: "ローソン\n合計 ¥378",
                source: .scan, confidence: .high, createdAt: created, updatedAt: created
            )
            context.insert(expense)
            expense.items = [
                KakeiboSchemaV1.LineItem(name: "からあげクン", priceYen: 238, isReducedRate: true, position: 0),
                KakeiboSchemaV1.LineItem(name: "緑茶", priceYen: 140, isReducedRate: true, position: 1),
            ]
            try context.save()
        }

        let container = try KakeiboStore.makeContainer(url: url)
        let context = ModelContext(container)
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        let expense = try #require(expenses.first)
        #expect(expenses.count == 1)
        #expect(expense.id == id)
        #expect(expense.dayKey == "2026-11-03")
        #expect(expense.time == "07:52")
        #expect(expense.storeName == "ローソン")
        #expect(expense.storeNameEn == "Lawson")
        #expect(expense.totalYen == 378)
        #expect(expense.tax8Yen == 28)
        #expect(expense.payment == .icCard)
        #expect(expense.category == .groceries)
        #expect(expense.invoiceNumber == "T6666666666666")
        #expect(expense.note == "朝ごはん")
        #expect(expense.photoFileName == "\(id).jpg")
        #expect(expense.source == .scan)
        #expect(expense.createdAt == created)
        #expect(expense.orderedItems.map(\.name) == ["からあげクン", "緑茶"])
        #expect(expense.receiptNumber == nil)

        // The new field is writable after migration.
        expense.receiptNumber = "1/2345"
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Expense>()).first?.receiptNumber == "1/2345")
    }
}
