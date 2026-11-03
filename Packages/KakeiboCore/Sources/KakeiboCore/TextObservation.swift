import Foundation

/// One piece of text found by OCR, with where it sits on the page.
///
/// Defined in Core (not Scan) so line reconstruction can be tested with `swift test`
/// from recorded observations, without Vision or a simulator.
public struct TextObservation: Sendable, Codable, Equatable {
    public var text: String
    /// Position on the page, normalized to 0–1, origin top-left.
    public var boundingBox: BoundingBox
    /// OCR confidence, 0–1.
    public var confidence: Double

    public init(text: String, boundingBox: BoundingBox, confidence: Double) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

/// A rectangle normalized to the page size (0–1), with the origin at the **top-left**
/// and `y` growing downward, like reading a receipt.
///
/// Vision uses a bottom-left origin; `fromBottomLeft` converts.
public struct BoundingBox: Sendable, Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Converts a normalized rectangle whose origin is bottom-left (Vision's convention).
    public static func fromBottomLeft(x: Double, y: Double, width: Double, height: Double) -> BoundingBox {
        BoundingBox(x: x, y: 1 - y - height, width: width, height: height)
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}
