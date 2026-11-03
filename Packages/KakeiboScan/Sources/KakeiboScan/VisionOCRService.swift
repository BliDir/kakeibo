import CoreGraphics
import Foundation
import KakeiboCore
import Vision

/// OCR with Vision's `RecognizeTextRequest`: Japanese and English, accurate level,
/// language correction on. Runs fully on the device.
///
/// Vision has its own `TextObservation`, so this file uses `OCRTextObservation` for ours.
public struct VisionOCRService: OCRService {
    public init() {}

    public func recognize(_ image: CGImage) async throws -> [OCRTextObservation] {
        let scaled = ImageDownscaler.downscale(image, maxPixelSize: KakeiboScan.maxOCRPixelSize)
        let observations = try await Self.makeRequest().perform(on: scaled)
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox.cgRect
            return OCRTextObservation(
                text: candidate.string,
                boundingBox: .fromBottomLeft(
                    x: Double(box.origin.x), y: Double(box.origin.y),
                    width: Double(box.width), height: Double(box.height)
                ),
                confidence: Double(candidate.confidence)
            )
        }
    }

    /// The configured request. Exposed for tests.
    static func makeRequest() -> RecognizeTextRequest {
        var request = RecognizeTextRequest()
        request.recognitionLanguages = KakeiboScan.recognitionLanguages.map { Locale.Language(identifier: $0) }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        return request
    }
}
