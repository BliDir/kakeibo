import Foundation
import KakeiboCore

/// Namespace for capture and reading: Vision OCR, VisionKit wrappers,
/// the Foundation Models refiner and `ExtractionPipeline` (later tickets).
public enum KakeiboScan {
    /// OCR languages, in priority order.
    public static let recognitionLanguages = ["ja-JP", "en-US"]
}
