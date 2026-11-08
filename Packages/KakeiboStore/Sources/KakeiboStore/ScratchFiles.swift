import Foundation

/// Short-lived files that hold ledger data or receipt images (v1.1, B-12): CSV exports and the
/// document camera's copies of scanned pages. While they exist they use
/// `FileProtectionType.complete` (unreadable while the iPhone is locked, like the store; see
/// `DataProtection`), and they are removed as soon as they are no longer needed:
///
/// - Exports (`tmp/Export`): each file is deleted when the share sheet finishes, whether it
///   was shared, saved or cancelled, and the folder is emptied when the export screen closes.
/// - Scanned pages (`Library/Caches/com.apple.DocumentCamera`, written by VisionKit): emptied
///   when the scan screen closes or the camera is cancelled. Not earlier: the page image
///   VisionKit returns can still read from its file.
/// - At launch, whatever a crash left behind in both is removed.
///
/// Photo library picks are loaded into memory and never written here; saved receipt photos
/// live in `PhotoStore`.
public enum ScratchFiles {
    /// CSV files waiting for the share sheet.
    public static var exportDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
    }

    /// VisionKit's document camera keeps its scanned pages here.
    public static func documentCameraDirectory() throws -> URL {
        try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("com.apple.DocumentCamera", isDirectory: true)
    }

    /// Creates `directory` if needed and gives it and its contents `.complete`, so files
    /// created inside later inherit it.
    public static func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try DataProtection.protect(directory)
    }

    /// Removes everything inside `directory` and keeps the folder (with its protection).
    /// A missing folder is nothing to do. Returns how many top-level items were removed.
    @discardableResult
    public static func empty(_ directory: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        let items = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for item in items { try FileManager.default.removeItem(at: item) }
        return items.count
    }

    /// Deletes one file. A missing file is fine.
    public static func remove(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Empties the document camera's folder and keeps it protected for the next scan.
    public static func clearScannedPages() throws {
        let directory = try documentCameraDirectory()
        try empty(directory)
        try prepare(directory)
    }

    /// Launch step: removes leftover exports and scanned pages (after a crash or a forced
    /// quit) and protects both folders. `extra` adds other scratch folders (Debug tools).
    public static func cleanUpAtLaunch(extra: [URL] = []) throws {
        try cleanUp([exportDirectory, try documentCameraDirectory()] + extra)
    }

    /// Empties and protects each folder. Every folder is tried; the first error is rethrown
    /// after the others are done.
    public static func cleanUp(_ directories: [URL]) throws {
        var firstError: (any Error)?
        for directory in directories {
            do {
                try empty(directory)
                try prepare(directory)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }
}
