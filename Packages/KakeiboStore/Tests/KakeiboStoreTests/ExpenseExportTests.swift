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

    @Test func preparedMonthHasCountTotalAndTheSameFile() throws {
        try add("2026-11-03", "ローソン", 378)
        try add("2026-11-01", "西友", 1_200)
        try add("2026-10-31", "ダイソー", 660)
        let month = LedgerMonth(year: 2026, month: 11)

        let prepared = try export.prepare(month: month)
        #expect(prepared.count == 2)
        #expect(prepared.totalYen == 1_578)
        #expect(!prepared.isEmpty)
        #expect(prepared.url.lastPathComponent == "kakeibo-2026-11.csv")
        // Exactly the bytes `file(for:)` writes: the CSV is unchanged.
        let fromPrepare = try Data(contentsOf: prepared.url)
        #expect(fromPrepare == (try Data(contentsOf: try export.file(for: month))))
    }

    @Test func preparedYearCountsTheWholeYear() throws {
        try add("2026-01-05", "A", 100)
        try add("2026-12-30", "B", 200)
        try add("2025-12-31", "C", 300)
        let prepared = try export.prepare(year: 2026)
        #expect(prepared.count == 2)
        #expect(prepared.totalYen == 300)
        #expect(prepared.url.lastPathComponent == "kakeibo-2026.csv")
    }

    @Test func preparedEmptyMonthIsEmpty() throws {
        let prepared = try export.prepare(month: LedgerMonth(year: 2026, month: 9))
        #expect(prepared.isEmpty)
        #expect(prepared.totalYen == 0)
    }

    @Test func prepareFailsWhenTheFolderCannotBeMade() throws {
        // A folder inside a file cannot be created.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ExportBlocker-\(UUID().uuidString)")
        try Data().write(to: file)
        let blocked = ExpenseExport(repository: repo, directory: file.appendingPathComponent("Export"))
        #expect(throws: (any Error).self) { try blocked.prepare(month: LedgerMonth(year: 2026, month: 11)) }
    }

    @Test func exportingAgainReplacesTheFile() throws {
        let month = LedgerMonth(year: 2026, month: 11)
        _ = try export.file(for: month)
        try add("2026-11-02", "New", 500)
        #expect(try rows(try export.file(for: month)).count == 2)
    }
    // MARK: Protection and clean-up (B-12)

    @Test(.enabled(if: DataProtectionTests.classesSupported)) func exportedFilesAreComplete() throws {
        try add("2026-11-03", "ローソン", 378)
        let file = try export.prepare(month: LedgerMonth(year: 2026, month: 11))
        #expect(DataProtection.protection(of: file.url) == .complete)
        #expect(DataProtection.protection(of: directory) == .complete)
    }

    /// The share sheet finished (shared, saved or cancelled): that file goes, the other stays
    /// until the export screen closes.
    @Test func removingASharedFileLeavesTheOther() throws {
        try add("2026-11-03", "ローソン", 378)
        let month = try export.prepare(month: LedgerMonth(year: 2026, month: 11))
        let year = try export.prepare(year: 2026)
        try export.remove(month.url)
        #expect(!FileManager.default.fileExists(atPath: month.url.path))
        #expect(FileManager.default.fileExists(atPath: year.url.path))
    }

    @Test func closingTheExportScreenRemovesEverything() throws {
        try add("2026-11-03", "ローソン", 378)
        _ = try export.prepare(month: LedgerMonth(year: 2026, month: 11))
        _ = try export.prepare(year: 2026)
        try export.removeAll()
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func removingTwiceIsFine() throws {
        let file = try export.prepare(month: LedgerMonth(year: 2026, month: 11))
        try export.remove(file.url)
        try export.remove(file.url)
        try export.removeAll()
        try ExpenseExport(repository: repo, directory: directory.appendingPathComponent("never")).removeAll()
    }

    /// Sharing again after the file was removed writes the same CSV again.
    @Test func exportingAfterRemovalWritesTheSameContent() throws {
        try add("2026-11-03", "ローソン", 378)
        let first = try export.prepare(month: LedgerMonth(year: 2026, month: 11))
        let bytes = try Data(contentsOf: first.url)
        try export.remove(first.url)
        let again = try export.prepare(month: LedgerMonth(year: 2026, month: 11))
        #expect(again == first)
        #expect(try Data(contentsOf: again.url) == bytes)
    }

    /// The file is exactly the CSV document: protection and clean-up change nothing in it.
    @Test func fileContentIsTheCSVDocument() throws {
        try add("2026-11-03", "ローソン", 378, items: [LineItemDraft(name: "緑茶", priceYen: 140, isReducedRate: true)])
        try add("2026-11-01", "=西友", 1_200)
        let file = try export.prepare(month: LedgerMonth(year: 2026, month: 11))
        let expected = ExpenseExport.csv(try repo.expenses(inMonth: "2026-11"))
        #expect(try Data(contentsOf: file.url) == expected)
        #expect(try rows(file.url).contains { $0.contains("'=西友") }, "formula guard still applied")
    }
}

/// Leftover scratch files and their folders (B-12).
@Suite struct ScratchFilesTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScratchFiles-\(UUID().uuidString)")

    private func makeFolder(_ name: String, files: [String]) throws -> URL {
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Scans"), withIntermediateDirectories: true)
        for file in files { try Data("x".utf8).write(to: folder.appendingPathComponent(file)) }
        return folder
    }

    /// After a crash: leftover exports and scanned pages (also in subfolders) are removed at launch.
    @Test func launchRemovesLeftovers() throws {
        let export = try makeFolder("Export", files: ["kakeibo-2026-11.csv", "kakeibo-2026.csv"])
        let camera = try makeFolder("com.apple.DocumentCamera", files: ["Scans/page.jpg"])
        try ScratchFiles.cleanUp([export, camera])
        #expect(try FileManager.default.contentsOfDirectory(atPath: export.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: camera.path).isEmpty)
    }

    @Test func launchCreatesMissingFoldersProtected() throws {
        let export = root.appendingPathComponent("Export")
        try ScratchFiles.cleanUp([export])
        #expect(FileManager.default.fileExists(atPath: export.path))
        if DataProtectionTests.classesSupported {
            #expect(DataProtection.protection(of: export) == .complete)
            // A scanned page written later inherits the folder's class.
            let page = export.appendingPathComponent("page.jpg")
            try Data("x".utf8).write(to: page)
            #expect(DataProtection.protection(of: page) == .complete)
        }
    }

    @Test func emptyingKeepsTheFolder() throws {
        let folder = try makeFolder("Export", files: ["a.csv"])
        #expect(try ScratchFiles.empty(folder) == 2)   // a.csv and Scans
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(try ScratchFiles.empty(root.appendingPathComponent("missing")) == 0)
    }

    @Test func oneFailingFolderDoesNotStopTheOthers() throws {
        let export = try makeFolder("Export", files: ["a.csv"])
        #expect(throws: (any Error).self) {
            try ScratchFiles.cleanUp([URL(fileURLWithPath: "/dev/null/Export"), export])
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: export.path).isEmpty)
    }
}
