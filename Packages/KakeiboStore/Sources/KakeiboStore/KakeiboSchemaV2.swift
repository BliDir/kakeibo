import Foundation
import KakeiboCore
import SwiftData

/// Version 2 of the on-disk schema: adds `Expense.receiptNumber` (T-48).
///
/// Copied from `KakeiboSchemaV1`; never edit these models once shipped (see V1 for the rules).
/// V1 → V2 is a lightweight migration: the only change is a new optional property.
public enum KakeiboSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Expense.self, LineItem.self]
    }

    @Model
    public final class Expense {
        #Index<Expense>([\.dayKey])

        @Attribute(.unique) public var id: UUID
        /// `yyyy-MM-dd` in Asia/Tokyo. Month and day grouping uses this, never `Date`.
        public var dayKey: String
        /// `HH:mm`, if printed.
        public var time: String?
        /// As printed, Japanese kept.
        public var storeName: String
        public var storeNameEn: String?
        /// Amount paid, tax included.
        public var totalYen: Int
        public var tax10Yen: Int?
        public var tax8Yen: Int?
        public var paymentRaw: String
        public var categoryRaw: String
        /// `T` + 13 digits.
        public var invoiceNumber: String?
        /// The receipt's own number, with the register when printed (`02/0012`). Used to spot
        /// a receipt saved twice. Nil for manual entries and receipts without one.
        public var receiptNumber: String?
        public var note: String
        @Relationship(deleteRule: .cascade, inverse: \LineItem.expense)
        public var items: [LineItem]
        /// File name inside `PhotoStore`.
        public var photoFileName: String?
        /// Raw OCR text, kept for review and re-parsing.
        public var ocrText: String?
        public var sourceRaw: String
        public var confidenceRaw: String
        public var createdAt: Date
        public var updatedAt: Date

        public init(
            id: UUID = UUID(),
            dayKey: String,
            time: String? = nil,
            storeName: String,
            storeNameEn: String? = nil,
            totalYen: Int,
            tax10Yen: Int? = nil,
            tax8Yen: Int? = nil,
            payment: PaymentMethod,
            category: ExpenseCategory,
            invoiceNumber: String? = nil,
            receiptNumber: String? = nil,
            note: String = "",
            items: [LineItem] = [],
            photoFileName: String? = nil,
            ocrText: String? = nil,
            source: ExpenseSource,
            confidence: Confidence,
            createdAt: Date,
            updatedAt: Date
        ) {
            self.id = id
            self.dayKey = dayKey
            self.time = time
            self.storeName = storeName
            self.storeNameEn = storeNameEn
            self.totalYen = totalYen
            self.tax10Yen = tax10Yen
            self.tax8Yen = tax8Yen
            self.paymentRaw = payment.rawValue
            self.categoryRaw = category.rawValue
            self.invoiceNumber = invoiceNumber
            self.receiptNumber = receiptNumber
            self.note = note
            self.items = items
            self.photoFileName = photoFileName
            self.ocrText = ocrText
            self.sourceRaw = source.rawValue
            self.confidenceRaw = confidence.rawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        public var payment: PaymentMethod {
            get { PaymentMethod(rawValue: paymentRaw) ?? .other }
            set { paymentRaw = newValue.rawValue }
        }

        public var category: ExpenseCategory {
            get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
            set { categoryRaw = newValue.rawValue }
        }

        public var source: ExpenseSource {
            get { ExpenseSource(rawValue: sourceRaw) ?? .manual }
            set { sourceRaw = newValue.rawValue }
        }

        public var confidence: Confidence {
            get { Confidence(rawValue: confidenceRaw) ?? .low }
            set { confidenceRaw = newValue.rawValue }
        }

        /// Items in receipt order. SwiftData does not keep relationship order, so use this.
        public var orderedItems: [LineItem] {
            items.sorted { $0.position < $1.position }
        }
    }

    @Model
    public final class LineItem {
        public var name: String
        public var nameEn: String?
        /// Negative for discounts (値引).
        public var priceYen: Int
        /// Marked ※ or ★ on the receipt (8% reduced rate).
        public var isReducedRate: Bool
        /// Order on the receipt, from 0.
        public var position: Int
        public var expense: Expense?

        public init(name: String, nameEn: String? = nil, priceYen: Int, isReducedRate: Bool = false, position: Int) {
            self.name = name
            self.nameEn = nameEn
            self.priceYen = priceYen
            self.isReducedRate = isReducedRate
            self.position = position
        }
    }
}
