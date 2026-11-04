import CoreGraphics
import Foundation
import ImageIO

/// Decodes photos the way they look on screen.
public enum ImageDecoding {
    /// An upright image from encoded data (JPEG, HEIC, PNG), with the EXIF orientation applied
    /// and the long side at most `maxPixelSize`.
    ///
    /// Plain `CGImageSourceCreateImageAtIndex` ignores orientation, so an iPhone portrait photo
    /// (orientation 6) would reach OCR sideways.
    public static func uprightImage(from data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
