import CoreGraphics
import Foundation
import ImageIO
import KakeiboCore
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import KakeiboStore

/// A fresh photo store in its own temporary directory, removed after the test.
final class TempPhotoStore {
    let root: URL
    let store: PhotoStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = try PhotoStore(directory: root.appendingPathComponent("Receipts", isDirectory: true))
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}

enum TestImages {
    /// A solid-colour image of the given size.
    static func cgImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Encoded image data with optional GPS and EXIF orientation, like a phone photo.
    static func data(type: UTType = .png, width: Int = 400, height: Int = 300,
                     gps: Bool = false, orientation: Int? = nil) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [:]
        if gps {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 35.6595, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 139.7005, kCGImagePropertyGPSLongitudeRef: "E",
            ]
        }
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, cgImage(width: width, height: height), properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func properties(of url: URL) -> [CFString: Any] {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
    }
}

@Suite struct PhotoStoreTests {
    @Test func savesJPEGWithUUIDName() throws {
        let temp = try TempPhotoStore()
        let name = try temp.store.save(imageData: TestImages.data())

        #expect(PhotoStore.isValidName(name))
        #expect(name.hasSuffix(".jpg"))
        let url = try temp.store.url(for: name)
        #expect(url.deletingLastPathComponent().lastPathComponent == "Receipts")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    }

    @Test func savesCGImage() throws {
        let temp = try TempPhotoStore()
        let name = try temp.store.save(image: TestImages.cgImage(width: 120, height: 80))
        let image = try #require(try temp.store.image(for: name))
        #expect((image.width, image.height) == (120, 80))
    }

    @Test func eachSaveGetsANewName() throws {
        let temp = try TempPhotoStore()
        let a = try temp.store.save(imageData: TestImages.data())
        let b = try temp.store.save(imageData: TestImages.data())
        #expect(a != b)
        #expect(try temp.store.storedNames().count == 2)
    }

    @Test func removesGPSAndKeepsOrientation() throws {
        let temp = try TempPhotoStore()
        let input = TestImages.data(type: .jpeg, gps: true, orientation: 6)
        // Make sure the input really has GPS, or the test proves nothing.
        let inputSource = try #require(CGImageSourceCreateWithData(input as CFData, nil))
        let inputProps = CGImageSourceCopyPropertiesAtIndex(inputSource, 0, nil) as! [CFString: Any]
        #expect(inputProps[kCGImagePropertyGPSDictionary] != nil)

        let name = try temp.store.save(imageData: input)
        let saved = TestImages.properties(of: try temp.store.url(for: name))
        #expect(saved[kCGImagePropertyGPSDictionary] == nil)
        #expect(saved[kCGImagePropertyOrientation] as? Int == 6)
    }

    @Test func rejectsNonImageData() throws {
        let temp = try TempPhotoStore()
        #expect(throws: PhotoStore.Error.unreadableImage) { try temp.store.save(imageData: Data("not an image".utf8)) }
        #expect(try temp.store.storedNames().isEmpty)
    }

    @Test func loadsDataAndImage() throws {
        let temp = try TempPhotoStore()
        let name = try temp.store.save(imageData: TestImages.data(width: 400, height: 300))
        #expect(try temp.store.data(for: name)?.isEmpty == false)
        let image = try #require(try temp.store.image(for: name))
        #expect((image.width, image.height) == (400, 300))
    }

    @Test func missingPhotoIsNil() throws {
        let temp = try TempPhotoStore()
        let name = UUID().uuidString + ".jpg"
        #expect(try temp.store.data(for: name) == nil)
        #expect(try temp.store.image(for: name) == nil)
        #expect(try temp.store.thumbnail(for: name) == nil)
    }

    @Test func thumbnailIsSmallAndUpright() throws {
        let temp = try TempPhotoStore()
        let name = try temp.store.save(imageData: TestImages.data(type: .jpeg, width: 3000, height: 2000, orientation: 6))
        let thumb = try #require(try temp.store.thumbnail(for: name))
        #expect(max(thumb.width, thumb.height) == PhotoStore.thumbnailPixelSize)
        // Orientation 6 rotates 90°, so the landscape pixels become a portrait thumbnail.
        #expect(thumb.height > thumb.width)
    }

    @Test(arguments: ["../secret.jpg", "abc.jpg", "photo.png", "", "/etc/passwd"])
    func rejectsNamesItDidNotCreate(name: String) throws {
        let temp = try TempPhotoStore()
        #expect(throws: PhotoStore.Error.invalidName(name)) { try temp.store.url(for: name) }
        #expect(throws: PhotoStore.Error.invalidName(name)) { try temp.store.delete(name) }
    }

    @Test func deleteIsIdempotent() throws {
        let temp = try TempPhotoStore()
        let name = try temp.store.save(imageData: TestImages.data())
        try temp.store.delete(name)
        #expect(try temp.store.storedNames().isEmpty)
        try temp.store.delete(name)
    }

    @Test func removeOrphansKeepsReferencedAndForeignFiles() throws {
        let temp = try TempPhotoStore()
        let kept = try temp.store.save(imageData: TestImages.data())
        _ = try temp.store.save(imageData: TestImages.data())
        _ = try temp.store.save(imageData: TestImages.data())
        let foreign = temp.store.directory.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: foreign)

        #expect(try temp.store.removeOrphans(keeping: [kept]) == 2)
        #expect(try temp.store.storedNames() == [kept])
        #expect(FileManager.default.fileExists(atPath: foreign.path))
    }

    @Test func totalBytesSumsPhotos() throws {
        let temp = try TempPhotoStore()
        #expect(try temp.store.totalBytes() == 0)
        let a = try temp.store.save(imageData: TestImages.data())
        let b = try temp.store.save(imageData: TestImages.data(width: 800, height: 600))
        let expected = try [a, b].reduce(Int64(0)) { sum, name in
            sum + Int64(try temp.store.data(for: name)!.count)
        }
        #expect(try temp.store.totalBytes() == expected)
        #expect(expected > 0)
    }

    @Test func filesAreIncludedInBackups() throws {
        let temp = try TempPhotoStore()
        let name = try temp.store.save(imageData: TestImages.data())
        let values = try temp.store.url(for: name).resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == false)
    }

    @Test func appDefaultIsApplicationSupportReceipts() throws {
        let store = try PhotoStore.appDefault()
        #expect(store.directory.lastPathComponent == "Receipts")
        #expect(store.directory.deletingLastPathComponent().lastPathComponent == "Application Support")
    }
}

@MainActor
@Suite struct RepositoryPhotoTests {
    let temp: TempPhotoStore
    let repo: ExpenseRepository

    init() throws {
        temp = try TempPhotoStore()
        repo = ExpenseRepository(container: try KakeiboStore.makeContainer(inMemory: true), photoStore: temp.store)
    }

    private func create(photo: String?) throws -> Expense {
        try repo.create(from: ReceiptDraft(dayKey: "2026-11-03", totalYen: 500), source: .scan, photoFileName: photo)
    }

    @Test func deletingExpenseDeletesItsPhoto() throws {
        let keepPhoto = try temp.store.save(imageData: TestImages.data())
        let gonePhoto = try temp.store.save(imageData: TestImages.data())
        _ = try create(photo: keepPhoto)
        let gone = try create(photo: gonePhoto)

        try repo.delete(gone)
        #expect(try temp.store.storedNames() == [keepPhoto])
    }

    @Test func deletingExpenseWithoutPhotoIsFine() throws {
        let photo = try temp.store.save(imageData: TestImages.data())
        _ = try create(photo: photo)
        try repo.delete(try create(photo: nil))
        #expect(try temp.store.storedNames() == [photo])
    }

    @Test func removeOrphanPhotosKeepsPhotosInUse() throws {
        let used = try temp.store.save(imageData: TestImages.data())
        _ = try temp.store.save(imageData: TestImages.data())   // e.g. a scan that was never saved
        _ = try create(photo: used)
        _ = try create(photo: nil)

        #expect(try repo.removeOrphanPhotos() == 1)
        #expect(try temp.store.storedNames() == [used])
    }
}
