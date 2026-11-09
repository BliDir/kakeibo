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

        var items = ItemParser.parse(lines: lines)
        var total = TotalExtractor.extract(lines: lines, itemPrices: items.map(\.priceYen))
        if let totalYen = total?.totalYen {
            // With the total known, the items also stop at a line showing it (B-15).
            let bounded = ItemParser.parse(lines: lines, totalYen: totalYen)
            if bounded != items {
                items = bounded
                total = TotalExtractor.extract(lines: lines, itemPrices: items.map(\.priceYen)) ?? total
            }
        }
        if let total {
            draft.totalYen = total.totalYen
            confidences[.totalYen] = total.confidence
        }
        // Items that add up to the total (tax included), the subtotal (tax added on top) or
        // the per-rate subtotals together (7-Eleven) were read completely. Otherwise one was
        // missed or misread: the review screen asks the user to check them.
        func addUp(_ items: [LineItemDraft]) -> Bool {
            guard !items.isEmpty else { return false }
            let sum = items.reduce(0) { $0 + $1.priceYen }
            let perRateSubtotals = total.map { $0.subtotalLinesYen.count > 1 ? $0.subtotalLinesYen.reduce(0, +) : nil } ?? nil
            return sum == total?.totalYen || sum == total?.subtotalYen || sum == perRateSubtotals
        }
        if !items.isEmpty, !addUp(items), total != nil,
           let repaired = ItemParser.repairShiftedPrices(lines: lines, totalYen: total?.totalYen, accepts: addUp) {
            // Prices one row off on a tilted photo (B-15), put back because only then do they add up.
            items = repaired
        }
        if !items.isEmpty {
            draft.items = items
            confidences[.items] = addUp(items) ? .high : .low
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
