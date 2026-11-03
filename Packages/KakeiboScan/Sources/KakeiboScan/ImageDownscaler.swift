import CoreGraphics
import Foundation

/// Shrinks images so their long side is at most a given size, keeping the aspect ratio.
public enum ImageDownscaler {
    /// Returns `image` unchanged when it already fits.
    public static func downscale(_ image: CGImage, maxPixelSize: Int) -> CGImage {
        let longSide = max(image.width, image.height)
        guard longSide > maxPixelSize, maxPixelSize > 0 else { return image }

        let scale = Double(maxPixelSize) / Double(longSide)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))

        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
