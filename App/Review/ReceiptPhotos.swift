import KakeiboStore
import UIKit

/// Receipt photos for the screens, decoded off the main thread.
///
/// A receipt photo is about 10 megapixels (24 for a library HEIC). Decoding one on the main
/// thread takes tens to hundreds of milliseconds, so the review screen used to freeze on every
/// keystroke while it redrew the full photo into a 44 pt row. Rows get a small preview; the
/// zoom view loads the full photo when it opens.
enum ReceiptPhotos {
    /// Long side of the receipt row preview (44 × 58 pt at 3×).
    static let previewPixelSize = 180
    /// Long side for the zoom view: large enough to keep every saved photo at full size.
    static let zoomPixelSize = 8192

    /// A photo not saved yet (review of a new scan), or the saved photo `storedName`.
    static func load(pending: ReviewForm.PendingPhoto?, storedName: String?, photoStore: PhotoStore?,
                     maxPixelSize: Int) async -> UIImage? {
        guard pending != nil || storedName != nil else { return nil }
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            if let pending { return pending.upright(maxPixelSize: maxPixelSize) }
            guard let storedName, let photoStore else { return nil }
            return try? photoStore.thumbnail(for: storedName, maxPixelSize: maxPixelSize)
        }.value
        return image.map { UIImage(cgImage: $0) }
    }
}
