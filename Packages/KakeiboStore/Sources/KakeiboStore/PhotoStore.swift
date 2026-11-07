import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Keeps the original receipt photo for each scanned expense as a JPEG file.
///
/// Files live in Application Support/Receipts, named `<UUID>.jpg`. They get the default
/// iOS data protection and are included in device backups (nothing opts them out).
/// GPS metadata is removed when a photo is saved; the camera orientation is kept.
public final class PhotoStore: Sendable {
    public enum Error: Swift.Error, Equatable {
        /// The data is not an image ImageIO can read.
        case unreadableImage
        /// Writing the JPEG failed.
        case encodingFailed
        /// The name is not one this store created (`<UUID>.jpg`).
        case invalidName(String)
    }

    /// JPEG quality for saved photos (about 0.3–0.6 MB per receipt).
    public static let jpegQuality = 0.8

    /// Long side of thumbnails for ledger rows, in pixels.
    public static let thumbnailPixelSize = 160

    public let directory: URL

    /// A store in `directory`, which is created if needed.
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The app's store: Application Support/Receipts.
    public static func appDefault() throws -> PhotoStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return try PhotoStore(directory: support.appendingPathComponent(KakeiboStore.photosDirectoryName, isDirectory: true))
    }

    // MARK: - Save

    /// Saves image data (JPEG, HEIC, PNG, ...) as a JPEG and returns the new file name.
    @discardableResult
    public func save(imageData: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { throw Error.unreadableImage }
        return try write { destination in
            // Copies the image with its orientation and other metadata, minus GPS.
            CGImageDestinationAddImageFromSource(destination, source, 0, Self.saveProperties)
        }
    }

    /// Saves a rendered image (for example from the document camera) as a JPEG and returns the new file name.
    @discardableResult
    public func save(image: CGImage) throws -> String {
        try write { destination in
            CGImageDestinationAddImage(destination, image, Self.saveProperties)
        }
    }

    private static var saveProperties: CFDictionary {
        [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
            kCGImagePropertyGPSDictionary: kCFNull!,
        ] as CFDictionary
    }

    private func write(_ add: (CGImageDestination) -> Void) throws -> String {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw Error.encodingFailed }
        add(destination)
        guard CGImageDestinationFinalize(destination) else { throw Error.encodingFailed }

        let name = UUID().uuidString + ".jpg"
        // .atomic avoids half-written files; no protection option, so the iOS default applies.
        try (data as Data).write(to: directory.appendingPathComponent(name), options: .atomic)
        return name
    }

    // MARK: - Load

    /// The file URL for a photo, for sharing or full-screen display.
    public func url(for name: String) throws -> URL {
        guard Self.isValidName(name) else { throw Error.invalidName(name) }
        return directory.appendingPathComponent(name)
    }

    /// The JPEG data, or nil when the file does not exist.
    public func data(for name: String) throws -> Data? {
        let url = try url(for: name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// The full-size image, or nil when the file does not exist.
    public func image(for name: String) throws -> CGImage? {
        guard let source = try imageSource(for: name) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }

    /// An upright image with the long side at most `maxPixelSize` (never enlarged), decoded
    /// now rather than when it is first drawn. Slow for big sizes: call it off the main actor.
    public func thumbnail(for name: String, maxPixelSize: Int = PhotoStore.thumbnailPixelSize) throws -> CGImage? {
        guard let source = try imageSource(for: name) else { return nil }
        return Self.thumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    static func thumbnail(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    private func imageSource(for name: String) throws -> CGImageSource? {
        let url = try url(for: name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return CGImageSourceCreateWithURL(url as CFURL, nil)
    }

    // MARK: - Delete and clean up

    /// Deletes a photo. Does nothing if the file is already gone.
    public func delete(_ name: String) throws {
        let url = try url(for: name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Deletes every photo whose name is not in `names`, and returns how many were deleted.
    /// Files this store did not create are left alone.
    @discardableResult
    public func removeOrphans(keeping names: Set<String>) throws -> Int {
        var removed = 0
        for name in try storedNames() where !names.contains(name) {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            removed += 1
        }
        return removed
    }

    /// Names of every photo in the store.
    public func storedNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter(Self.isValidName).sorted()
    }

    // MARK: - Usage

    /// Total size of all photos, in bytes, for the Settings screen.
    public func totalBytes() throws -> Int64 {
        try storedNames().reduce(Int64(0)) { sum, name in
            let values = try directory.appendingPathComponent(name).resourceValues(forKeys: [.fileSizeKey])
            return sum + Int64(values.fileSize ?? 0)
        }
    }

    // MARK: - Names

    /// `<UUID>.jpg`, so a name can never point outside the directory.
    static func isValidName(_ name: String) -> Bool {
        guard name.hasSuffix(".jpg") else { return false }
        return UUID(uuidString: String(name.dropLast(4))) != nil
    }
}
