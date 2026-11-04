import Foundation
import KakeiboCore

/// Applies a refinement that finished while the user was already editing the review form.
///
/// A field takes the refined value only if the user has not changed it from the parser's
/// value. Its confidence follows the value that was kept. Items are replaced only when the
/// user has not touched them.
public enum BackgroundRefinement {
    /// - Parameters:
    ///   - refined: what `ExtractionPipeline.refine` returned.
    ///   - original: the parser draft the form started from.
    ///   - current: the form's draft now, with the user's edits.
    public static func apply(refined: ReceiptDraft, original: ReceiptDraft, current: ReceiptDraft) -> ReceiptDraft {
        var result = current

        func take<T: Equatable>(_ path: WritableKeyPath<ReceiptDraft, T>, _ field: ReceiptField?) {
            guard current[keyPath: path] == original[keyPath: path] else { return }
            result[keyPath: path] = refined[keyPath: path]
            if let field { result.confidences[field] = refined.confidences[field] }
        }

        take(\.storeName, .storeName)
        take(\.storeNameEn, nil)
        take(\.dayKey, .dayKey)
        take(\.time, .time)
        take(\.totalYen, .totalYen)
        take(\.tax10Yen, .tax10Yen)
        take(\.tax8Yen, .tax8Yen)
        take(\.payment, .payment)
        take(\.category, .category)
        take(\.invoiceNumber, .invoiceNumber)
        take(\.items, .items)
        return result
    }
}
