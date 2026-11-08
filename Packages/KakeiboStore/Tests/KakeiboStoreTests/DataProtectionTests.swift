import Foundation
import KakeiboCore
import SwiftData
import Testing
@testable import KakeiboStore

/// iOS data protection for the ledger and receipt photos (B-11).
///
/// macOS (`swift test`) and iPhones report and set protection classes; the iOS simulator does
/// not (it reports none), so tests of the classes themselves run only where
/// `classesSupported`. Tests that the upgrade loses nothing and the store still opens run
/// everywhere. The device check is in `CLAUDE.md` (`KAKEIBO_PROTECTION_REPORT`).
@MainActor
@Suite struct DataProtectionTests {
    /// Whether this system keeps protection classes on files.
    nonisolated static let classesSupported: Bool = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("protection-probe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? Data().write(to: url, options: .completeFileProtection)) != nil else { return false }
        return DataProtection.protection(of: url) == .complete
    }()

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DataProtection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func protection(_ url: URL) -> FileProtectionType? { DataProtection.protection(of: url) }

    /// Checks the class where the system keeps classes (not on the simulator).
    private func expectClass(_ entries: [DataProtection.Entry], _ expected: FileProtectionType = .complete,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        guard Self.classesSupported else { return }
        for entry in entries {
            #expect(entry.protection == expected, "\(entry.path)", sourceLocation: sourceLocation)
        }
    }

    private func setProtection(_ type: FileProtectionType, _ url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: type], ofItemAtPath: url.path)
    }

    /// Application Support as a v1.0 user has it: the store with its journal files and the
    /// photo folder, all with the iOS default class.
    private func makeV1_0Folder() throws -> (store: URL, photo: URL, contents: [URL: Data]) {
        let receipts = root.appendingPathComponent("Receipts")
        try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
        var contents: [URL: Data] = [:]
        let store = root.appendingPathComponent("default.store")
        for (name, bytes) in [("default.store", "sqlite"), ("default.store-wal", "wal"), ("default.store-shm", "shm")] {
            contents[root.appendingPathComponent(name)] = Data(bytes.utf8)
        }
        let photo = receipts.appendingPathComponent("\(UUID().uuidString).jpg")
        contents[photo] = TestImages.data(type: .jpeg)
        for (url, data) in contents { try data.write(to: url) }
        for url in [root, receipts] + Array(contents.keys) {
            try setProtection(.completeUntilFirstUserAuthentication, url)
        }
        return (store, photo, contents)
    }

    // MARK: New files

    @Test(.enabled(if: classesSupported)) func savedPhotosAreComplete() throws {
        let temp = try TempPhotoStore()
        let fromData = try temp.store.save(imageData: TestImages.data())
        let fromImage = try temp.store.save(image: TestImages.cgImage(width: 20, height: 30))
        #expect(protection(try temp.store.url(for: fromData)) == .complete)
        #expect(protection(try temp.store.url(for: fromImage)) == .complete)
    }

    @Test(.enabled(if: classesSupported)) func photoFolderIsCompleteSoNewFilesInheritIt() throws {
        let temp = try TempPhotoStore()
        #expect(protection(temp.store.directory) == .complete)
        let other = temp.store.directory.appendingPathComponent("other.tmp")
        try Data("x".utf8).write(to: other)
        #expect(protection(other) == .complete)
    }

    /// The store and its journal get `.complete` once the folder is protected, and the store
    /// opens and saves as usual. SQLite sets the `-shm` index's class itself (no ledger data).
    @Test func storeInAProtectedFolderIsCompleteAndSaves() throws {
        try DataProtection.protect(root)
        let url = root.appendingPathComponent("default.store")
        let container = try KakeiboStore.makeContainer(url: url)
        let repository = ExpenseRepository(container: container)
        try repository.create(from: ReceiptDraft(storeName: "ローソン", dayKey: "2026-11-07", totalYen: 378), source: .manual)

        let entries = DataProtection.report(root).filter { $0.path.hasPrefix("default.store") }
        #expect(Set(entries.map(\.path)) == ["default.store", "default.store-wal", "default.store-shm"])
        expectClass(entries.filter { $0.path != "default.store-shm" })
        #expect(try repository.expenses(inMonth: "2026-11").map(\.totalYen) == [378])
    }

    // MARK: Upgrading v1.0 files

    @Test func upgradesV1_0FilesWithoutChangingThem() throws {
        let (_, _, contents) = try makeV1_0Folder()
        let changed = try DataProtection.protect(root)

        if Self.classesSupported {
            // The files except the -shm index, Receipts and the folder itself.
            #expect(changed == contents.count - 1 + 2)
        }
        expectClass(DataProtection.report(root).filter { $0.path != "default.store-shm" })
        for (url, data) in contents { #expect(try Data(contentsOf: url) == data, "\(url.lastPathComponent)") }
    }

    @Test(.enabled(if: classesSupported)) func upgradingAgainChangesNothing() throws {
        _ = try makeV1_0Folder()
        try DataProtection.protect(root)
        #expect(try DataProtection.protect(root) == 0)
    }

    @Test(.enabled(if: classesSupported)) func photosAddedAfterTheUpgradeAreComplete() throws {
        _ = try makeV1_0Folder()
        try DataProtection.protect(root)
        let photos = try PhotoStore(directory: root.appendingPathComponent("Receipts"))
        let name = try photos.save(imageData: TestImages.data())
        #expect(protection(try photos.url(for: name)) == .complete)
        #expect(try photos.storedNames().count == 2)
    }

    /// The populated v1.0 store (schema V2) still migrates and saves after its files are upgraded.
    @Test func upgradedV1_0StoreOpensMigratesAndSaves() throws {
        let fixture = try #require(Bundle.module.url(forResource: "Fixtures/v2-store", withExtension: nil))
        let folder = root.appendingPathComponent("store")
        try FileManager.default.copyItem(at: fixture, to: folder)
        for entry in DataProtection.report(folder) {
            try setProtection(.completeUntilFirstUserAuthentication, folder.appendingPathComponent(entry.path))
        }
        try DataProtection.protect(folder)

        let container = try KakeiboStore.makeContainer(url: folder.appendingPathComponent("Kakeibo.store"))
        let repository = ExpenseRepository(container: container)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Expense>()) == 3)
        try repository.create(from: ReceiptDraft(storeName: "ダイソー", dayKey: "2026-11-07", totalYen: 660), source: .manual)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Expense>()) == 4)
        expectClass(DataProtection.report(folder).filter { !$0.path.hasSuffix("-shm") })
    }

    /// SQLite resets the `-shm` index on every open, so the upgrade skips it rather than
    /// changing it on every launch.
    @Test(.enabled(if: classesSupported)) func sqliteIndexIsLeftToSQLite() throws {
        let (_, _, contents) = try makeV1_0Folder()
        try DataProtection.protect(root)
        let shm = root.appendingPathComponent("default.store-shm")
        #expect(protection(shm) == .completeUntilFirstUserAuthentication)
        #expect(try Data(contentsOf: shm) == contents[shm])
    }

    @Test func missingFolderIsNothingToDo() throws {
        #expect(try DataProtection.protect(root.appendingPathComponent("nope")) == 0)
        #expect(DataProtection.report(root.appendingPathComponent("nope")).isEmpty)
    }

    /// Protection never opts anything out of backups (the architecture doc: normal OS backups
    /// may contain app data).
    @Test func upgradeLeavesBackupsOn() throws {
        let (store, photo, _) = try makeV1_0Folder()
        try DataProtection.protect(root)
        for url in [root, store, photo] {
            #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == false)
        }
    }

    @Test func reportListsPathsRelativeToTheFolder() throws {
        let (_, photo, _) = try makeV1_0Folder()
        let paths = DataProtection.report(root).map(\.path)
        #expect(paths.first == ".")
        #expect(paths.contains("default.store-wal"))
        #expect(paths.contains("Receipts/\(photo.lastPathComponent)"))
    }
}
