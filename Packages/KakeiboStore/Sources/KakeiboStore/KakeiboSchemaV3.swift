import Foundation
import KakeiboCore
import SwiftData

/// Version 3 of the on-disk schema: adds monthly budgets (v1.1, B-02).
///
/// `Expense` and `LineItem` are copied unchanged from `KakeiboSchemaV2`; the new models are
/// `BudgetMonth`, `BudgetTemplate` and `BudgetAlertIntent`. Never edit these models once
/// shipped (see V1 for the rules). V2 → V3 is a lightweight migration: new entities only, so
/// existing expenses, items and photo names are kept as they are and no budget is created.
public enum KakeiboSchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Expense.self, LineItem.self, BudgetMonth.self, BudgetTemplate.self, BudgetAlertIntent.self]
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

    // MARK: Budgets (v1.1, B-02)

    /// One month's budget and alert state, one row per `yyyy-MM` (unique).
    ///
    /// A row exists once the month has been set up: a budget was set, the template was applied,
    /// or an alert was handled. `budgetYen == nil` means no budget (never set, or removed);
    /// the row stays so the month's alert history survives a remove and re-add, and so the
    /// template is never applied to it afterwards.
    @Model
    public final class BudgetMonth {
        /// `yyyy-MM`, Tokyo.
        @Attribute(.unique) public var monthKey: String
        /// Whole yen, 1 ... `MonthlyBudget.maximumYen`; nil when there is no budget.
        public var budgetYen: Int?
        /// True when `budgetYen` came from the future-month template, not typed for this month.
        public var appliedFromTemplate: Bool
        /// The 80% alert has been handled this month (emitted, or skipped because 100% came first).
        public var handledEighty: Bool
        /// The 100% alert has been handled this month.
        public var handledHundred: Bool
        public var createdAt: Date
        public var updatedAt: Date

        public init(monthKey: String, budgetYen: Int? = nil, appliedFromTemplate: Bool = false,
                    handledEighty: Bool = false, handledHundred: Bool = false, createdAt: Date, updatedAt: Date) {
            self.monthKey = monthKey
            self.budgetYen = budgetYen
            self.appliedFromTemplate = appliedFromTemplate
            self.handledEighty = handledEighty
            self.handledHundred = handledHundred
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        /// The budget as Core reads it (`.unset` when removed or never set).
        public var budget: MonthlyBudget { MonthlyBudget.validated(budgetYen) }

        /// Thresholds already handled this month.
        public var handledThresholds: Set<BudgetThreshold> {
            var set: Set<BudgetThreshold> = []
            if handledEighty { set.insert(.eighty) }
            if handledHundred { set.insert(.hundred) }
            return set
        }
    }

    /// "Use this amount for future months": at most one row. Off (no row) by default.
    @Model
    public final class BudgetTemplate {
        /// Always `BudgetTemplate.singletonKey`, so there can be only one.
        @Attribute(.unique) public var key: String
        public var amountYen: Int
        /// First month (`yyyy-MM`) it may be applied to: the month after it was last saved.
        public var startMonthKey: String
        public var createdAt: Date
        public var updatedAt: Date

        public static let singletonKey = "default"

        public init(amountYen: Int, startMonthKey: String, createdAt: Date, updatedAt: Date) {
            key = Self.singletonKey
            self.amountYen = amountYen
            self.startMonthKey = startMonthKey
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    /// A local notification Kakeibo decided to send for a threshold, kept so it survives a
    /// relaunch and is never sent twice. One row per month and threshold (unique `requestID`).
    @Model
    public final class BudgetAlertIntent {
        /// Stable notification request ID: `budget-<yyyy-MM>-<threshold>`.
        @Attribute(.unique) public var requestID: String
        public var monthKey: String
        /// `BudgetThreshold` raw value (80 or 100). Stored on disk; never change the values.
        public var thresholdRaw: Int
        /// `BudgetAlertIntentState` raw value. Stored on disk; never rename.
        public var stateRaw: String
        public var createdAt: Date
        public var updatedAt: Date

        public init(monthKey: String, threshold: BudgetThreshold, state: BudgetAlertIntentState, createdAt: Date, updatedAt: Date) {
            requestID = Self.requestID(monthKey: monthKey, threshold: threshold)
            self.monthKey = monthKey
            thresholdRaw = threshold.rawValue
            stateRaw = state.rawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        public static func requestID(monthKey: String, threshold: BudgetThreshold) -> String {
            "budget-\(monthKey)-\(threshold.rawValue)"
        }

        public var threshold: BudgetThreshold? { BudgetThreshold(rawValue: thresholdRaw) }

        public var state: BudgetAlertIntentState {
            get { BudgetAlertIntentState(rawValue: stateRaw) ?? .cancelled }
            set { stateRaw = newValue.rawValue }
        }
    }
}
