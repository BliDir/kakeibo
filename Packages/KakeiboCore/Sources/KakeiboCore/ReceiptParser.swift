import Foundation

/// Turns OCR lines into a `ReceiptDraft`. Rule-based, works on every iPhone, no network.
///
/// Steps: `TextNormalizer`, then `StoreClassifier`, `DateTimeParser`, `TotalExtractor`,
/// `TaxExtractor` (given the total), `InvoiceNumberParser` and `PaymentMethodDetector`.
/// Each field gets the confidence its parser reported. Item lines arrive in T-17.
public enum ReceiptParser {
    /// - Parameters:
    ///   - lines: raw OCR lines, one per receipt row, top to bottom.
    ///   - today: the scan date, used for month-day dates and to spot dates in the future.
    public static func parse(lines: [String], today: Date) -> ReceiptDraft {
        let lines = TextNormalizer.normalize(lines: lines)
        var draft = ReceiptDraft()
        var confidences: [ReceiptField: Confidence] = [:]

        let store = StoreClassifier.classify(lines: lines)
        draft.storeName = store.storeName
        draft.storeNameEn = store.storeNameEn
        draft.category = store.category
        if store.storeName != nil { confidences[.storeName] = store.storeConfidence }
        confidences[.category] = store.categoryConfidence

        let dateTime = DateTimeParser.parse(lines: lines, today: today)
        if let date = dateTime.date {
            draft.dayKey = date.dayKey
            confidences[.dayKey] = date.confidence
        }
        if let time = dateTime.time {
            draft.time = time
            // A time is easy to misread and has no cross-check.
            confidences[.time] = .medium
        }

        let total = TotalExtractor.extract(lines: lines)
        if let total {
            draft.totalYen = total.totalYen
            confidences[.totalYen] = total.confidence
        }

        if let tax = TaxExtractor.extract(lines: lines, totalYen: total?.totalYen) {
            draft.tax10Yen = tax.tax10Yen
            draft.tax8Yen = tax.tax8Yen
            if tax.tax10Yen != nil { confidences[.tax10Yen] = tax.confidence }
            if tax.tax8Yen != nil { confidences[.tax8Yen] = tax.confidence }
        }

        if let invoice = InvoiceNumberParser.parse(lines: lines) {
            draft.invoiceNumber = invoice.invoiceNumber
            confidences[.invoiceNumber] = invoice.confidence
        }

        let payment = PaymentMethodDetector.detect(lines: lines)
        draft.payment = payment.payment
        confidences[.payment] = payment.confidence

        draft.confidences = confidences
        return draft
    }

    /// Convenience for OCR text with one receipt row per line.
    public static func parse(text: String, today: Date) -> ReceiptDraft {
        parse(lines: text.components(separatedBy: .newlines), today: today)
    }
}
