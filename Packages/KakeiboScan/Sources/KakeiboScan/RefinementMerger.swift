import Foundation
import KakeiboCore

/// Combines the parser draft with what the model read.
///
/// - Total: the parser's total is kept when its arithmetic check passed (`high`).
///   Otherwise, when both have a total and they differ, the parser's total is kept and marked
///   `low` so the review screen highlights it. A total only the model found is used, marked `low`.
/// - Store, date, tax and payment: the model fills only what the parser did not find
///   (a payment the parser merely defaulted to cash counts as not found). Filled fields are `medium`.
/// - Category: when the model supplies the store and the parser had no category match,
///   the model's store name is run through the chain dictionary.
/// - Items: the model's items are used when the parser has none; otherwise the parser's
///   items are kept and the model only adds missing English names.
/// - Model values that make no sense (bad dates, non-positive totals, zero tax, tax at or above
///   the total) are ignored, and so are "items" that are really summary lines (小計, 合計, お預り,
///   お釣り, tax, points): the model sometimes lists them.
public enum RefinementMerger {
    public static func merge(draft: ReceiptDraft, model: ModelReceipt) -> ReceiptDraft {
        var result = draft
        let modelTotal = model.totalYen.flatMap { (1...TotalExtractor.maximumYen).contains($0) ? $0 : nil }

        // Total.
        if let parserTotal = draft.totalYen {
            let checked = draft.confidence(for: .totalYen) == .high
            if !checked, let modelTotal, modelTotal != parserTotal {
                result.confidences[.totalYen] = .low
            }
        } else if let modelTotal {
            result.totalYen = modelTotal
            result.confidences[.totalYen] = .low
        }
        let total = result.totalYen

        // Store, date, tax, payment: fill gaps only.
        if draft.storeName == nil, let store = model.storeName?.trimmingCharacters(in: .whitespaces), !store.isEmpty {
            result.storeName = store
            result.confidences[.storeName] = .medium
            if draft.confidence(for: .category) == .low {
                let classified = StoreClassifier.classify(lines: [store])
                if classified.category != .other {
                    result.category = classified.category
                    result.storeNameEn = result.storeNameEn ?? classified.storeNameEn
                    result.confidences[.category] = .medium
                }
            }
        }
        if draft.dayKey == nil, let day = model.dayKey, DayKey.isValid(day) {
            result.dayKey = day
            result.confidences[.dayKey] = .medium
        }
        func validTax(_ value: Int?) -> Int? {
            // A tax of 0 means the receipt has no such rate; leave the field empty.
            guard let value, value > 0 else { return nil }
            if let total, value >= total { return nil }
            return value
        }
        if draft.tax10Yen == nil, let tax = validTax(model.tax10Yen) {
            result.tax10Yen = tax
            result.confidences[.tax10Yen] = .medium
        }
        if draft.tax8Yen == nil, let tax = validTax(model.tax8Yen) {
            result.tax8Yen = tax
            result.confidences[.tax8Yen] = .medium
        }
        let parserFoundPayment = draft.payment != nil && draft.confidence(for: .payment) != .low
        if !parserFoundPayment, let payment = model.payment {
            result.payment = payment
            result.confidences[.payment] = .medium
        }

        // Items.
        let modelItems = model.items.filter { item in
            let name = item.name.trimmingCharacters(in: .whitespaces)
            return !name.isEmpty && !summaryWords.contains { name.contains($0) }
        }
        if draft.items.isEmpty {
            if !modelItems.isEmpty {
                result.items = modelItems
                result.confidences[.items] = .medium
            }
        } else {
            result.items = draft.items.map { item in
                guard item.nameEn == nil,
                      let match = modelItems.first(where: { $0.name == item.name && $0.priceYen == item.priceYen })
                else { return item }
                var filled = item
                filled.nameEn = match.nameEn
                return filled
            }
        }
        return result
    }

    /// Words that mark a summary line, never an item. Discounts (値引, 割引) are items.
    static let summaryWords = ["小計", "合計", "お預", "預り", "預かり", "お釣", "釣銭", "おつり",
                               "消費税", "内税", "外税", "税等", "対象", "ポイント", "残高"]
}
