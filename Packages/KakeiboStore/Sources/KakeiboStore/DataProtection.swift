import Foundation

/// iOS data protection for the ledger and receipt photos (v1.1, B-11).
///
/// Everything in Application Support (the SwiftData store and its `-wal` journal, and the
/// Receipts folder) uses `FileProtectionType.complete`: unreadable from shortly after the
/// iPhone locks until it is unlocked again. v1.0 files had the iOS default,
/// `.completeUntilFirstUserAuthentication` (readable while locked once the phone had been
/// unlocked after a restart).
///
/// The one exception is the store's `-shm` file. SQLite gives it
/// `.completeUntilFirstUserAuthentication` itself every time the store opens, whatever its
/// folder has. It is the journal's index (page numbers and offsets) and holds no ledger data,
/// so it is left alone rather than fought over on every launch.
///
/// `.complete` is safe for the store because Kakeibo reads and writes it only in the
/// foreground: v1.1 has no background tasks, and budget alerts are decided after a save or on
/// launch, foreground and Tokyo midnight while the app is open. A read or save that still
/// lands after locking fails like any other store error (the ledger keeps what it shows, a
/// save shows the failure panel).
///
/// The protection class does not change backups: iCloud and computer backups still include
/// the app's data. Settings (UserDefaults) stay with iOS's default.
public enum DataProtection {
    /// The class for the ledger and receipt photos.
    public static let protectionClass: FileProtectionType = .complete

    public enum Error: Swift.Error, Equatable {
        /// These paths could not be given the protection class.
        case couldNotProtect([String])
    }

    /// One file or folder and its protection class (nil where the system reports none).
    public struct Entry: Sendable, Equatable, CustomStringConvertible {
        public let path: String
        public let protection: FileProtectionType?

        public var description: String {
            "\(path): \(protection.map { $0.rawValue } ?? "none")"
        }
    }

    /// Application Support: the SwiftData store (`default.store`) and the Receipts folder.
    public static func appDataDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    /// Launch step: upgrades v1.0 files (and anything else left with a weaker class) in
    /// Application Support. Run it before opening the store, so its `-wal`/`-shm` files
    /// inherit the class too.
    @discardableResult
    public static func protectAppData() throws -> Int {
        try protect(appDataDirectory())
    }

    /// `directory` and everything in it with its protection class, relative to `directory`.
    public static func report(_ directory: URL) -> [Entry] {
        let base = directory.resolvingSymlinksInPath().path
        return items(in: directory).map { url in
            let relative = url.resolvingSymlinksInPath().path.dropFirst(base.count)
            return Entry(path: relative.isEmpty ? "." : String(relative.drop { $0 == "/" }), protection: protection(of: url))
        }
    }

    /// Gives `directory` and everything in it `protectionClass`. Files created inside later
    /// inherit it from their folder. Items that already have it are left alone, so this is
    /// cheap and safe to run on every launch. Returns how many items it changed.
    ///
    /// Every item is tried; if some fail, the rest are still protected and the error lists
    /// the failures.
    @discardableResult
    public static func protect(_ directory: URL) throws -> Int {
        var changed = 0
        var failed: [String] = []
        for url in items(in: directory) where !isSQLiteIndex(url) && protection(of: url) != protectionClass {
            do {
                try FileManager.default.setAttributes([.protectionKey: protectionClass], ofItemAtPath: url.path)
                changed += 1
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        if !failed.isEmpty { throw Error.couldNotProtect(failed) }
        return changed
    }

    /// The protection class of one file or folder.
    public static func protection(of url: URL) -> FileProtectionType? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.protectionKey] as? FileProtectionType
    }

    /// SQLite's `-shm` index, whose class SQLite sets itself (see the type's notes).
    public static func isSQLiteIndex(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix("-shm")
    }

    /// The folder first, then everything under it (symbolic links are left out).
    private static func items(in directory: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        var children: [URL] = []
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])
        while let url = enumerator?.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
            children.append(url)
        }
        return [directory] + children.sorted { $0.path < $1.path }
    }
}
