import Foundation

/// The fields read from a receipt, before the user confirms them.
///
/// Every field is optional because OCR may miss it. Money is whole yen.
public struct ReceiptDraft: Sendable, Codable, Equatable {
    /// Store name as printed, Japanese kept.
    public var storeName: String?
    public var storeNameEn: String?
    /// Purchase date as `yyyy-MM-dd` (Asia/Tokyo).
    public var dayKey: String?
    /// Purchase time as `HH:mm`, if printed.
    public var time: String?
    /// Amount paid, tax included.
    public var totalYen: Int?
    /// Consumption tax at 10%.
    public var tax10Yen: Int?
    /// Consumption tax at the 8% reduced rate.
    public var tax8Yen: Int?
    public var payment: PaymentMethod?
    public var category: ExpenseCategory?
    /// Invoice registration number (登録番号): `T` + 13 digits.
    public var invoiceNumber: String?
    public var items: [LineItemDraft]
    /// Confidence per field. Fields not listed count as `.low`.
    public var confidences: [ReceiptField: Confidence]

    public init(
        storeName: String? = nil,
        storeNameEn: String? = nil,
        dayKey: String? = nil,
        time: String? = nil,
        totalYen: Int? = nil,
        tax10Yen: Int? = nil,
        tax8Yen: Int? = nil,
        payment: PaymentMethod? = nil,
        category: ExpenseCategory? = nil,
        invoiceNumber: String? = nil,
        items: [LineItemDraft] = [],
        confidences: [ReceiptField: Confidence] = [:]
    ) {
        self.storeName = storeName
        self.storeNameEn = storeNameEn
        self.dayKey = dayKey
        self.time = time
        self.totalYen = totalYen
        self.tax10Yen = tax10Yen
        self.tax8Yen = tax8Yen
        self.payment = payment
        self.category = category
        self.invoiceNumber = invoiceNumber
        self.items = items
        self.confidences = confidences
    }

    /// Confidence for one field, `.low` when none was recorded.
    public func confidence(for field: ReceiptField) -> Confidence {
        confidences[field] ?? .low
    }
}

/// The fields of a `ReceiptDraft` that carry a confidence.
public enum ReceiptField: String, CaseIterable, Sendable, Codable, Equatable, CodingKeyRepresentable {
    case storeName
    case dayKey
    case time
    case totalYen
    case tax10Yen
    case tax8Yen
    case payment
    case category
    case invoiceNumber
    case items
}

/// One item line on a receipt.
public struct LineItemDraft: Sendable, Codable, Equatable {
    /// Item name as printed.
    public var name: String
    public var nameEn: String?
    /// Price in yen. Negative for discounts (値引).
    public var priceYen: Int
    /// True when the line is marked ※ or ★ (8% reduced rate).
    public var isReducedRate: Bool

    public init(name: String, nameEn: String? = nil, priceYen: Int, isReducedRate: Bool = false) {
        self.name = name
        self.nameEn = nameEn
        self.priceYen = priceYen
        self.isReducedRate = isReducedRate
    }
}
