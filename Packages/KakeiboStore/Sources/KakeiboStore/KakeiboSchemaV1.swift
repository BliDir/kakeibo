import Foundation
import KakeiboCore
import SwiftData

/// Version 1 of the on-disk schema (v1.0).
///
/// Never edit these models once shipped. To change the schema, copy them into
/// `KakeiboSchemaV2`, change the copy, add a stage to `KakeiboMigrationPlan`,
/// and point the top-level typealiases at the new version.
///
/// Enums are stored as their raw-value strings (`paymentRaw`, `categoryRaw`, ...)
/// so predicates can filter on them and migrations stay simple. Use the typed
/// computed properties in code.
public enum KakeiboSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

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

/// The current schema's models.
public typealias Expense = KakeiboSchemaV1.Expense
public typealias LineItem = KakeiboSchemaV1.LineItem

/// Migrations between schema versions. v1.0 has only one version, so no stages yet.
public enum KakeiboMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [KakeiboSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}

public enum KakeiboStore {
    /// Folder name for receipt photos inside Application Support.
    public static let photosDirectoryName = "Receipts"

    /// The app's model container, using the current schema and migration plan.
    /// - Parameter inMemory: true for tests and previews; nothing is written to disk.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: KakeiboSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, migrationPlan: KakeiboMigrationPlan.self, configurations: configuration)
    }
}
