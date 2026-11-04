import Foundation

/// A calendar month in the ledger (Asia/Tokyo).
public struct LedgerMonth: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    /// 1–12.
    public let month: Int

    public init(year: Int, month: Int) {
        precondition((1...12).contains(month), "month must be 1–12")
        self.year = year
        self.month = month
    }

    /// The month containing `date` in Asia/Tokyo.
    public init(containing date: Date) {
        let key = DayKey.make(from: date)
        self.init(year: Int(key.prefix(4))!, month: Int(key.dropFirst(5).prefix(2))!)
    }

    /// The month of a `yyyy-MM-dd` dayKey, or nil when it is not valid.
    public init?(dayKey: String) {
        guard DayKey.isValid(dayKey) else { return nil }
        self.init(year: Int(dayKey.prefix(4))!, month: Int(dayKey.dropFirst(5).prefix(2))!)
    }

    /// `yyyy-MM`, as `ExpenseRepository.expenses(inMonth:)` takes it.
    public var key: String { String(format: "%04d-%02d", year, month) }
    public var description: String { key }

    public var previous: LedgerMonth {
        month == 1 ? LedgerMonth(year: year - 1, month: 12) : LedgerMonth(year: year, month: month - 1)
    }

    public var next: LedgerMonth {
        month == 12 ? LedgerMonth(year: year + 1, month: 1) : LedgerMonth(year: year, month: month + 1)
    }

    /// Noon on the 1st, Tokyo, for formatting the month name.
    public var firstDay: Date { DayKey.date(from: key + "-01")! }

    public static func < (a: LedgerMonth, b: LedgerMonth) -> Bool {
        (a.year, a.month) < (b.year, b.month)
    }
}

/// Japanese era (和暦) labels for months, as printed on receipts and used in tax documents.
public enum JapaneseEra {
    /// `令和8年11月` for November 2026. Reiwa began in May 2019; earlier months are 平成.
    public static func label(for month: LedgerMonth) -> String {
        let (name, year) = era(for: month)
        return "\(name)\(year == 1 ? "元" : String(year))年\(month.month)月"
    }

    /// `Reiwa 8` for any month of 2026.
    public static func englishYear(for month: LedgerMonth) -> String {
        let (name, year) = era(for: month)
        return "\(name == "令和" ? "Reiwa" : "Heisei") \(year)"
    }

    private static func era(for month: LedgerMonth) -> (String, Int) {
        if month >= LedgerMonth(year: 2019, month: 5) {
            return ("令和", month.year - 2018)
        }
        return ("平成", month.year - 1988)
    }
}

/// What the ledger needs from a saved expense. `Expense` (KakeiboStore) conforms.
public protocol LedgerItem {
    var dayKey: String { get }
    var totalYen: Int { get }
    var tax10Yen: Int? { get }
    var tax8Yen: Int? { get }
    var category: ExpenseCategory { get }
}

/// Totals for one month.
public struct MonthSummary: Sendable, Equatable {
    public var totalYen: Int
    public var count: Int
    /// Consumption tax paid (8% + 10%), as printed on the receipts.
    public var taxYen: Int
    /// Spending per category, largest first; categories with nothing spent are left out.
    public var categories: [CategoryTotal]

    public struct CategoryTotal: Sendable, Equatable {
        public var category: ExpenseCategory
        public var totalYen: Int
        /// Share of the month's total, 0–1.
        public var share: Double
    }

    public static let empty = MonthSummary(totalYen: 0, count: 0, taxYen: 0, categories: [])

    public init(totalYen: Int, count: Int, taxYen: Int, categories: [CategoryTotal]) {
        self.totalYen = totalYen
        self.count = count
        self.taxYen = taxYen
        self.categories = categories
    }

    public init(_ items: [some LedgerItem]) {
        let total = items.reduce(0) { $0 + $1.totalYen }
        var byCategory: [ExpenseCategory: Int] = [:]
        for item in items { byCategory[item.category, default: 0] += item.totalYen }
        let categories = byCategory
            .filter { $0.value > 0 }
            .map { CategoryTotal(category: $0.key, totalYen: $0.value, share: total > 0 ? Double($0.value) / Double(total) : 0) }
            // Largest first; ties in the fixed category order so the bar does not jump.
            .sorted { a, b in
                a.totalYen != b.totalYen
                    ? a.totalYen > b.totalYen
                    : ExpenseCategory.allCases.firstIndex(of: a.category)! < ExpenseCategory.allCases.firstIndex(of: b.category)!
            }
        self.init(
            totalYen: total,
            count: items.count,
            taxYen: items.reduce(0) { $0 + ($1.tax8Yen ?? 0) + ($1.tax10Yen ?? 0) },
            categories: categories
        )
    }
}

/// One day in the ledger: its expenses and subtotal.
public struct DayGroup<Item: LedgerItem> {
    public var dayKey: String
    /// In the order given (the repository returns newest first).
    public var items: [Item]
    public var subtotalYen: Int { items.reduce(0) { $0 + $1.totalYen } }

    /// Groups by day, newest day first, keeping each day's item order.
    public static func group(_ items: [Item]) -> [DayGroup<Item>] {
        var order: [String] = []
        var byDay: [String: [Item]] = [:]
        for item in items {
            if byDay[item.dayKey] == nil { order.append(item.dayKey) }
            byDay[item.dayKey, default: []].append(item)
        }
        return order.sorted(by: >).map { DayGroup(dayKey: $0, items: byDay[$0]!) }
    }
}
