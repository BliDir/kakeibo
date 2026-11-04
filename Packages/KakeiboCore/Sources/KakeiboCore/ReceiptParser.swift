import Foundation

/// Turns OCR lines into a `ReceiptDraft`. Rule-based, works on every iPhone, no network.
///
/// Steps: `TextNormalizer`, then `StoreClassifier`, `DateTimeParser`, `ItemParser`,
/// `TotalExtractor` (given the item prices, for the item-sum check), `TaxExtractor` (given the
/// total), `InvoiceNumberParser`, `ReceiptNumberParser` and `PaymentMethodDetector`.
/// Each field gets the confidence its parser reported.
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

        let items = ItemParser.parse(lines: lines)
        let total = TotalExtractor.extract(lines: lines, itemPrices: items.map(\.priceYen))
        if let total {
            draft.totalYen = total.totalYen
            confidences[.totalYen] = total.confidence
        }
        if !items.isEmpty {
            draft.items = items
            // Items that add up to the total or the subtotal were read completely.
            let sum = items.reduce(0) { $0 + $1.priceYen }
            let adds = sum == total?.totalYen || sum == total?.subtotalYen
            confidences[.items] = adds ? .high : .medium
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

        if let receipt = ReceiptNumberParser.parse(lines: lines) {
            draft.receiptNumber = receipt.receiptNumber
            confidences[.receiptNumber] = receipt.confidence
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
