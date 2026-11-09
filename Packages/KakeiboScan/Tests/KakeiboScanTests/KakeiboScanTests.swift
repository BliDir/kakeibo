import CoreGraphics
import Foundation
import ImageIO
import KakeiboCore
import Testing
import Vision
@testable import KakeiboScan

enum ScanTestImages {
    static func solid(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// The bundled made-up receipt (see scripts/make-sample-receipt.swift).
    static func sampleReceipt() throws -> CGImage { try bundled("sample-receipt") }

    /// A bundled image from SampleImages.
    static func bundled(_ name: String) throws -> CGImage {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "SampleImages"))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    static func bundledData(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "SampleImages"))
        return try Data(contentsOf: url)
    }
}

@Suite struct ImageDownscalerTests {
    @Test func shrinksLongSideKeepingAspect() {
        let scaled = ImageDownscaler.downscale(ScanTestImages.solid(width: 4000, height: 6000), maxPixelSize: 3000)
        #expect((scaled.width, scaled.height) == (2000, 3000))
    }

    @Test func shrinksLandscape() {
        let scaled = ImageDownscaler.downscale(ScanTestImages.solid(width: 4032, height: 3024), maxPixelSize: 3000)
        #expect((scaled.width, scaled.height) == (3000, 2250))
    }

    @Test func leavesSmallImagesAlone() {
        let image = ScanTestImages.solid(width: 3000, height: 1200)
        #expect(ImageDownscaler.downscale(image, maxPixelSize: 3000) === image)
    }

    @Test func ocrLimitIs3000() {
        #expect(KakeiboScan.maxOCRPixelSize == 3000)
    }
}

@Suite struct VisionOCRServiceTests {
    @Test func requestIsConfiguredForJapaneseReceipts() {
        let request = VisionOCRService.makeRequest()
        #expect(request.recognitionLanguages.map(\.maximalIdentifier).first?.hasPrefix("ja") == true)
        #expect(request.recognitionLanguages.count == 2)
        #expect(request.recognitionLevel == .accurate)
        #expect(request.usesLanguageCorrection)
    }

    @Test func japaneseIsFirstRecognitionLanguage() {
        #expect(KakeiboScan.recognitionLanguages == ["ja-JP", "en-US"])
    }

    /// Integration test: real Vision OCR on the bundled sample receipt.
    @Test func readsSampleReceipt() async throws {
        let observations = try await VisionOCRService().recognize(try ScanTestImages.sampleReceipt())
        let texts = observations.map(\.text)
        print("OCR lines:\n" + texts.joined(separator: "\n"))

        #expect(texts.contains { $0.contains("合計") })
        #expect(texts.contains { $0.contains("754") })

        for observation in observations {
            let box = observation.boundingBox
            #expect(box.minX >= -0.01 && box.maxX <= 1.01 && box.minY >= -0.01 && box.maxY <= 1.01)
            #expect((0...1).contains(observation.confidence))
        }

        // Top-left origin: the store name is above 合計, which is above お釣り.
        func y(_ fragment: String) throws -> Double {
            try #require(observations.first { $0.text.contains(fragment) }, "no \(fragment)").boundingBox.midY
        }
        #expect(try y("サンプル") < y("合計"))
        #expect(try y("合計") < y("釣"))
    }

    @Test func emptyImageGivesNoText() async throws {
        let observations = try await VisionOCRService().recognize(ScanTestImages.solid(width: 600, height: 800))
        #expect(observations.isEmpty)
    }
}

@Suite struct VisionBaselineSlopeTests {
    /// Vision's points are bottom-left: a right corner lower on the page has a smaller y.
    @Test func slopeIsInTopLeftCoordinates() {
        let slope = VisionOCRService.slope(from: NormalizedPoint(x: 0.1, y: 0.5), to: NormalizedPoint(x: 0.6, y: 0.45))
        #expect(abs(slope! - 0.1) < 1e-9)
        #expect(VisionOCRService.slope(from: NormalizedPoint(x: 0.5, y: 0.5), to: NormalizedPoint(x: 0.5, y: 0.4)) == nil)
    }
}
