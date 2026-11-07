import CoreGraphics
import Foundation
import ImageIO

extension ReviewForm.PendingPhoto {
    /// Writes the photo to `photoStore` and returns its file name. Slow for a full-size photo:
    /// call it off the main actor.
    func save(to photoStore: PhotoStore) throws -> String {
        switch self {
        case .image(let image): try photoStore.save(image: image)
        case .data(let data): try photoStore.save(imageData: data)
        }
    }

    /// An upright copy with the long side at most `maxPixelSize`, for previews. The camera
    /// image comes back as it is when it is already small enough. Decoding a library photo
    /// is slow: call it off the main actor.
    public func upright(maxPixelSize: Int) -> CGImage? {
        switch self {
        case .data(let data):
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) > 0 else { return nil }
            return PhotoStore.thumbnail(from: source, maxPixelSize: maxPixelSize)
        case .image(let image):
            return Self.downscaled(image, maxPixelSize: maxPixelSize)
        }
    }

    static func downscaled(_ image: CGImage, maxPixelSize: Int) -> CGImage? {
        let longSide = max(image.width, image.height)
        guard longSide > maxPixelSize else { return image }
        let scale = Double(maxPixelSize) / Double(longSide)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
