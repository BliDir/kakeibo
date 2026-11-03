import CoreGraphics
import Foundation
import KakeiboCore

/// Reads text from a receipt image on the device.
public protocol OCRService: Sendable {
    /// Text found in the image, each with a normalized top-left bounding box.
    func recognize(_ image: CGImage) async throws -> [TextObservation]
}

/// Our `TextObservation`, under a name that does not clash with Vision's type of the same name.
/// Declared here because this file does not import Vision. (`KakeiboCore.TextObservation`
/// does not work: the `KakeiboCore` enum hides the module name.)
public typealias OCRTextObservation = TextObservation

public enum KakeiboScan {
    /// OCR languages, in priority order.
    public static let recognitionLanguages = ["ja-JP", "en-US"]

    /// Images are downscaled to this long side before OCR. Larger images are slower
    /// and do not read better.
    public static let maxOCRPixelSize = 3000
}
