import Foundation
import KakeiboCore
import SwiftData
import Testing
@testable import KakeiboStore

/// Upgrading to the budget schema (V3) from a populated v1.0 store.
///
/// v1.0 ships with schema V2, so `Fixtures/v2-store` is the store a v1.0 user has: three
/// expenses with items, a receipt number and photo names, written by V2 only. Like the V1
/// fixture it is a checked-in file, never written during a normal test run (see
/// `SchemaMigrationTests` for why). To rewrite it (only if V2 data must change, which it
/// should not once shipped):
///
///     KAKEIBO_WRITE_V2_FIXTURE=1 swift test --package-path Packages/KakeiboStore --filter writeV2Fixture
@MainActor
@Suite struct BudgetMigrationTests {
    static let created = Date(timeIntervalSince1970: 1_793_674_800)   // 2026-11-03 12:00 Tokyo
    static let ids = [
        UUID(uuidString: "4C0E7B1A-0B2D-4D5E-8F10-1A2B3C4D5E01")!,
        UUID(uuidString: "4C0E7B1A-0B2D-4D5E-8F10-1A2B3C4D5E02")!,
        UUID(uuidString: "4C0E7B1A-0B2D-4D5E-8F10-1A2B3C4D5E03")!,
    ]

    /// Copies a fixture store into a temporary folder and returns the store file's URL.
    private func copyFixture(_ name: String) throws -> (url: URL, folder: URL) {
        let fixture = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil),
                                   "\(name) fixture missing from the test bundle")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BudgetMigration-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: fixture, to: folder)
        return (folder.appendingPathComponent("Kakeibo.store"), folder)
    }

    @Test func populatedV1_0StoreKeepsEverythingAndGetsNoBudget() throws {
        let (url, folder) = try copyFixture("v2-store")
        defer { try? FileManager.default.removeItem(at: folder) }

        // A photo file the store refers to, and a setting, as a v1.0 user would have.
        let photos = try PhotoStore(directory: folder.appendingPathComponent("Receipts"))
        let photoName = "\(Self.ids[0]).jpg"
        try Data([0xFF, 0xD8, 0xFF]).write(to: photos.url(for: photoName))
        let suite = "BudgetMigration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        AppSettings(defaults: defaults).defaultPayment = .icCard

        let container = try KakeiboStore.makeContainer(url: url)
        let expenses = ExpenseRepository(container: container, photoStore: photos)

        // Expenses, items, receipt numbers and photo names are unchanged.
        let all = try container.mainContext.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.dayKey)]))
        #expect(all.map(\.id) == [Self.ids[2], Self.ids[1], Self.ids[0]])
        #expect(all.map(\.totalYen) == [2_150, 1_078, 378])
        let lawson = try #require(all.first { $0.id == Self.ids[0] })
        #expect(lawson.storeName == "ローソン")
        #expect(lawson.receiptNumber == "1/2345")
        #expect(lawson.invoiceNumber == "T6666666666666")
        #expect(lawson.photoFileName == photoName)
        #expect(lawson.orderedItems.map(\.name) == ["からあげクン", "緑茶"])
        #expect(lawson.orderedItems.map(\.priceYen) == [238, 140])
        #expect(try expenses.expenses(inMonth: "2026-11").count == 3)

        // The photo is still referenced, so cleaning up keeps it.
        #expect(try expenses.removeOrphanPhotos() == 0)
        #expect(FileManager.default.fileExists(atPath: try photos.url(for: photoName).path))

        // Settings live outside the store and are untouched.
        #expect(AppSettings(defaults: defaults).defaultPayment == .icCard)

        // Nothing budget-related exists or turns on by itself.
        let context = container.mainContext
        #expect(try context.fetch(FetchDescriptor<BudgetMonth>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BudgetTemplate>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BudgetAlertIntent>()).isEmpty)
        let budgets = BudgetRepository(container: container)
        #expect(try budgets.budget(for: LedgerMonth(year: 2026, month: 11), now: Self.created) == .unset)
        #expect(try budgets.template() == nil)

        // And the upgraded store takes budgets.
        try budgets.setBudget(80_000, for: LedgerMonth(year: 2026, month: 11), now: Self.created)
        #expect(try budgets.budget(for: LedgerMonth(year: 2026, month: 11), now: Self.created) == .yen(80_000))
    }

    @Test func originalV1StoreUpgradesThroughToBudgets() throws {
        let (url, folder) = try copyFixture("v1-store")
        defer { try? FileManager.default.removeItem(at: folder) }
        let container = try KakeiboStore.makeContainer(url: url)
        #expect(try container.mainContext.fetch(FetchDescriptor<Expense>()).count == 1)
        #expect(try container.mainContext.fetch(FetchDescriptor<BudgetMonth>()).isEmpty)
        #expect(try BudgetRepository(container: container).template() == nil)
    }

    /// Writes `Fixtures/v2-store` with schema V2 only, as v1.0 of the app does.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["KAKEIBO_WRITE_V2_FIXTURE"] == "1"))
    func writeV2Fixture() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/v2-store", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let schema = Schema(versionedSchema: KakeiboSchemaV2.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(
            schema: schema, url: folder.appendingPathComponent("Kakeibo.store")))
        let context = ModelContext(container)
        let lawson = KakeiboSchemaV2.Expense(
            id: Self.ids[0], dayKey: "2026-11-03", time: "07:52", storeName: "ローソン", storeNameEn: "Lawson",
            totalYen: 378, tax8Yen: 28, payment: .icCard, category: .groceries,
            invoiceNumber: "T6666666666666", receiptNumber: "1/2345", note: "朝ごはん",
            photoFileName: "\(Self.ids[0]).jpg", ocrText: "ローソン\n合計 ¥378",
            source: .scan, confidence: .high, createdAt: Self.created, updatedAt: Self.created
        )
        context.insert(lawson)
        lawson.items = [
            KakeiboSchemaV2.LineItem(name: "からあげクン", priceYen: 238, isReducedRate: true, position: 0),
            KakeiboSchemaV2.LineItem(name: "緑茶", priceYen: 140, isReducedRate: true, position: 1),
        ]
        context.insert(KakeiboSchemaV2.Expense(
            id: Self.ids[1], dayKey: "2026-11-02", storeName: "スターバックス", totalYen: 1_078, tax10Yen: 98,
            payment: .credit, category: .dining, source: .manual, confidence: .high,
            createdAt: Self.created, updatedAt: Self.created
        ))
        context.insert(KakeiboSchemaV2.Expense(
            id: Self.ids[2], dayKey: "2026-11-01", storeName: "JR東日本", totalYen: 2_150,
            payment: .icCard, category: .transport, source: .manual, confidence: .high,
            createdAt: Self.created, updatedAt: Self.created
        ))
        try context.save()
    }
}
