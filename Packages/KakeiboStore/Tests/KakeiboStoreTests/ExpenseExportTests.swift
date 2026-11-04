import Foundation
import KakeiboCore
import Testing
@testable import KakeiboStore

@MainActor
@Suite struct ExpenseExportTests {
    let repo: ExpenseRepository
    let export: ExpenseExport
    let directory: URL
    static let now = Date(timeIntervalSince1970: 1_793_674_800)

    init() throws {
        repo = ExpenseRepository(container: try KakeiboStore.makeContainer(inMemory: true))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ExportTests-\(UUID().uuidString)")
        export = ExpenseExport(repository: repo, directory: directory)
    }

    private func add(_ day: String, _ store: String, _ total: Int, items: [LineItemDraft] = [], now: Date = now) throws {
        try repo.create(from: ReceiptDraft(storeName: store, dayKey: day, totalYen: total, payment: .cash,
                                           category: .groceries, items: items),
                        source: .manual, note: "", now: now)
    }

    private func rows(_ url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        return String(decoding: data.dropFirst(3), as: UTF8.self)
            .components(separatedBy: "\r\n").filter { !$0.isEmpty }
    }

    @Test func monthFileHasTheMonthOldestFirst() throws {
        try add("2026-11-03", "ローソン", 378)
        try add("2026-11-01", "西友", 1_200, items: [LineItemDraft(name: "牛乳", priceYen: 198, isReducedRate: true),
                                                     LineItemDraft(name: "洗剤", priceYen: 398)])
        try add("2026-10-31", "ダイソー", 660)

        let url = try export.file(for: LedgerMonth(year: 2026, month: 11))
        #expect(url.lastPathComponent == "kakeibo-2026-11.csv")
        let lines = try rows(url)
        #expect(lines.count == 3)
        #expect(lines[1] == "2026-11-01,西友,食料品,現金,1200,,,,牛乳 198 ※; 洗剤 398,")
        #expect(lines[2].hasPrefix("2026-11-03,ローソン,"))
    }

    @Test func yearFileHasTheWholeYear() throws {
        try add("2026-01-05", "A", 100)
        try add("2026-12-30", "B", 200)
        try add("2025-12-31", "C", 300)
        let url = try export.file(forYear: 2026)
        #expect(url.lastPathComponent == "kakeibo-2026.csv")
        let lines = try rows(url)
        #expect(lines.dropFirst().map { $0.prefix(10) } == ["2026-01-05", "2026-12-30"])
    }

    @Test func sameDayRowsFollowSaveOrder() throws {
        try add("2026-11-02", "First", 100, now: Self.now)
        try add("2026-11-02", "Second", 200, now: Self.now.addingTimeInterval(60))
        let lines = try rows(try export.file(for: LedgerMonth(year: 2026, month: 11)))
        #expect(lines[1].contains(",First,"))
        #expect(lines[2].contains(",Second,"))
    }

    @Test func emptyMonthStillHasTheHeader() throws {
        let lines = try rows(try export.file(for: LedgerMonth(year: 2026, month: 9)))
        #expect(lines == ["date,store,category,payment,total_yen,tax10_yen,tax8_yen,invoice_no,items,note"])
    }

    @Test func exportingAgainReplacesTheFile() throws {
        let month = LedgerMonth(year: 2026, month: 11)
        _ = try export.file(for: month)
        try add("2026-11-02", "New", 500)
        #expect(try rows(try export.file(for: month)).count == 2)
    }
}
