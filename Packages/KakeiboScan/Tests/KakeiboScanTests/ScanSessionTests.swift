import CoreGraphics
import Foundation
import ImageIO
import KakeiboCore
import Testing
import UniformTypeIdentifiers
@testable import KakeiboScan

private let scanDay = Date(timeIntervalSince1970: 1_793_674_800)

private let rows = [
    TextObservation(text: "合計", boundingBox: BoundingBox(x: 0.05, y: 0.5, width: 0.2, height: 0.03), confidence: 0.9),
    TextObservation(text: "¥754", boundingBox: BoundingBox(x: 0.6, y: 0.5, width: 0.2, height: 0.03), confidence: 0.9),
]

/// Encodes `image` as JPEG with an EXIF orientation tag.
private func jpeg(_ image: CGImage, orientation: Int) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    CGImageDestinationFinalize(destination)
    return data as Data
}

/// The image turned 90° anticlockwise: what a camera stores for a portrait shot tagged orientation 6.
private func rotatedAnticlockwise(_ image: CGImage) -> CGImage {
    let context = CGContext(
        data: nil, width: image.height, height: image.width, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.translateBy(x: CGFloat(image.height), y: 0)
    context.rotate(by: .pi / 2)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()!
}

@Suite struct ImageDecodingTests {
    @Test func appliesOrientationAndLimitsSize() {
        let wide = ScanTestImages.solid(width: 4000, height: 3000)
        let decoded = ImageDecoding.uprightImage(from: jpeg(wide, orientation: 6), maxPixelSize: 3000)
        // Orientation 6 turns landscape pixels into a portrait image.
        #expect(decoded?.width == 2250)
        #expect(decoded?.height == 3000)
    }

    @Test func rejectsNonImages() {
        #expect(ImageDecoding.uprightImage(from: Data("nope".utf8), maxPixelSize: 3000) == nil)
    }

    /// An iPhone portrait photo of a receipt: pixels sideways, orientation tag 6.
    @Test func portraitPhotoIsReadUpright() async throws {
        let sideways = jpeg(rotatedAnticlockwise(try ScanTestImages.sampleReceipt()), orientation: 6)
        let pipeline = ExtractionPipeline(ocr: VisionOCRService(), refiner: NoopRefiner(), now: { scanDay })
        let result = try await pipeline.extract(imageData: sideways)
        #expect(result.draft.totalYen == 754)
    }
}

@MainActor
@Suite struct ScanSessionTests {
    private func session(_ ocr: MockOCR) -> ScanSession {
        ScanSession(pipeline: ExtractionPipeline(ocr: ocr, refiner: NoopRefiner(), now: { scanDay }))
    }

    @Test func readsCapturedPage() async {
        let s = session(MockOCR(observations: rows))
        s.start(image: ScanTestImages.solid(width: 600, height: 900))
        #expect(s.phase == .processing(.readingText))
        #expect(s.source == .camera)
        #expect(s.image != nil)

        await s.waitUntilFinished()
        #expect(s.phase == .finished)
        #expect(s.result?.draft.totalYen == 754)
        #expect(s.imageData == nil)
    }

    @Test func readsLibraryPhotoAndKeepsOriginalData() async throws {
        let data = try ScanTestImages.bundledData("sample-receipt")
        let s = session(MockOCR(observations: rows))
        s.start(imageData: data)
        #expect(s.source == .photoLibrary)
        await s.waitUntilFinished()
        #expect(s.phase == .finished)
        #expect(s.imageData == data)
    }

    @Test func showsUnderstandingStage() async {
        let s = session(MockOCR(observations: rows, delay: .milliseconds(300)))
        s.start(image: ScanTestImages.solid(width: 600, height: 900))
        // Still reading while OCR is busy.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(s.phase == .processing(.readingText))
        await s.waitUntilFinished()
        #expect(s.phase == .finished)
    }

    @Test func noTextFails() async {
        let s = session(MockOCR(observations: []))
        s.start(image: ScanTestImages.solid(width: 600, height: 900))
        await s.waitUntilFinished()
        #expect(s.phase == .failed(.noTextFound))
        #expect(s.result == nil)
    }

    @Test func undecodablePhotoFailsAtOnce() {
        let s = session(MockOCR(observations: rows))
        s.start(imageData: Data("not an image".utf8))
        #expect(s.phase == .failed(.unreadableImage))
        #expect(s.image == nil)
    }

    @Test func cancelKeepsNothing() async {
        let s = session(MockOCR(observations: rows, delay: .seconds(10)))
        s.start(image: ScanTestImages.solid(width: 600, height: 900))
        try? await Task.sleep(for: .milliseconds(50))
        s.cancel()
        #expect(s.phase == .idle)
        #expect(s.image == nil && s.result == nil && s.source == nil)

        let start = ContinuousClock.now
        await s.waitUntilFinished()
        #expect(ContinuousClock.now - start < .seconds(1))
        // A late result must not bring the session back.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(s.phase == .idle)
    }

    @Test func startingAgainReplacesThePreviousScan() async {
        let s = session(MockOCR(observations: rows, delay: .milliseconds(200)))
        s.start(image: ScanTestImages.solid(width: 600, height: 900))
        s.start(image: ScanTestImages.solid(width: 700, height: 900))
        await s.waitUntilFinished()
        #expect(s.phase == .finished)
        #expect(s.image?.width == 700)
    }
}
