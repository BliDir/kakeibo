import Foundation
import KakeiboCore
import SwiftData
import Testing
@testable import KakeiboStore

/// Opens a store written by schema V1 (v1.0 of the app) with the current schema and migration plan.
///
/// The V1 store is a checked-in file (`Fixtures/v1-store`), not written during the test run:
/// creating a V1 container while other suites create V2 containers in the same process makes
/// SwiftData mix up the two `Expense` models, and the test crashes now and then on iOS.
/// The app itself never creates a V1 container; it only opens the store with the migration plan.
///
/// To rewrite the fixture (only if V1 data must change, which it should not once shipped):
///
///     KAKEIBO_WRITE_V1_FIXTURE=1 swift test --package-path Packages/KakeiboStore --filter writeV1Fixture
@Suite struct SchemaMigrationTests {
    static let id = UUID(uuidString: "7D3F0A52-6B1E-4C1A-9E55-2B8C1D4E6F70")!
    static let created = Date(timeIntervalSince1970: 1_793_674_800)

    @Test func v1StoreSurvivesMigrationToV2() throws {
        let fixture = try #require(
            Bundle.module.url(forResource: "Fixtures/v1-store", withExtension: nil),
            "v1-store fixture missing from the test bundle"
        )
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MigrationTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.copyItem(at: fixture, to: folder)
        let url = folder.appendingPathComponent("Kakeibo.store")

        let container = try KakeiboStore.makeContainer(url: url)
        let context = ModelContext(container)
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        let expense = try #require(expenses.first)
        #expect(expenses.count == 1)
        #expect(expense.id == Self.id)
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
        #expect(expense.photoFileName == "\(Self.id).jpg")
        #expect(expense.source == .scan)
        #expect(expense.createdAt == Self.created)
        #expect(expense.orderedItems.map(\.name) == ["からあげクン", "緑茶"])
        #expect(expense.receiptNumber == nil)

        // The new field is writable after migration.
        expense.receiptNumber = "1/2345"
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Expense>()).first?.receiptNumber == "1/2345")
    }

    /// Writes `Fixtures/v1-store` with schema V1 only, as v1.0 of the app did.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["KAKEIBO_WRITE_V1_FIXTURE"] == "1"))
    func writeV1Fixture() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/v1-store", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Kakeibo.store")

        let schema = Schema(versionedSchema: KakeiboSchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let context = ModelContext(container)
        let expense = KakeiboSchemaV1.Expense(
            id: Self.id, dayKey: "2026-11-03", time: "07:52", storeName: "ローソン", storeNameEn: "Lawson",
            totalYen: 378, tax8Yen: 28, payment: .icCard, category: .groceries,
            invoiceNumber: "T6666666666666", note: "朝ごはん", photoFileName: "\(Self.id).jpg",
            ocrText: "ローソン\n合計 ¥378", source: .scan, confidence: .high,
            createdAt: Self.created, updatedAt: Self.created
        )
        context.insert(expense)
        expense.items = [
            KakeiboSchemaV1.LineItem(name: "からあげクン", priceYen: 238, isReducedRate: true, position: 0),
            KakeiboSchemaV1.LineItem(name: "緑茶", priceYen: 140, isReducedRate: true, position: 1),
        ]
        try context.save()
    }
}
