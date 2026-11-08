import Foundation

// Spending baseline, pace comparison, projection and insight state (v1.2, BI-01).
//
// Rules (Kakeibo iOS v1.2 Budget Insights spec):
// - Baseline months: up to the last 3 closed months before the analysed month that have at
//   least one expense. Empty months are skipped. None at all is "limited history".
// - Pace-adjusted baseline for a category or store: its average spend per baseline month ×
//   elapsed days ÷ days in month (months with no spend in that category count as 0). A closed
//   month is compared full month to full month.
// - Projection: spent ÷ elapsed days × days in month, only for the current month and only from
//   day 5.
// - Insight state, with B-01 spend semantics (S = `MonthSpend.total`, refunds included):
//   current month over budget (S > B); on pace to overspend (S ≥ 80% of B, or projection > B,
//   and S ≤ B); closed month over budget (final S > B); otherwise none.
// All amounts are whole yen, rounded down, and overflow-checked; dates are Tokyo dayKeys and
// `Calendar.kakeibo`. Nothing here reads the clock or traps.

/// What insights need from a saved expense: the ledger fields and the store.
/// `Expense` (KakeiboStore) conforms.
public protocol InsightItem: LedgerItem {
    /// As saved (the canonical chain name when the store is known). Empty means unknown.
    var storeName: String { get }
}

// MARK: - Pace

/// How much of a month the comparison covers.
public struct MonthPace: Sendable, Equatable {
    /// Days of the month that have started, today included (all of them for a closed month).
    public let elapsedDays: Int
    public let daysInMonth: Int

    /// Before `projectionStartDay` the month-end projection is too noisy to show.
    public static let projectionStartDay = 5

    /// The pace of `month` at `now`: partial for the current month, full for a closed month,
    /// nil for a future month.
    public init?(month: LedgerMonth, now: Date, calendar: Calendar = .kakeibo) {
        guard let first = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1, hour: 12)),
              let days = calendar.range(of: .day, in: .month, for: first)?.count else { return nil }
        let current = LedgerMonth(containing: now)
        if month < current {
            self.init(elapsedDays: days, daysInMonth: days)
        } else if month == current {
            self.init(elapsedDays: calendar.component(.day, from: now), daysInMonth: days)
        } else {
            return nil
        }
    }

    init(elapsedDays: Int, daysInMonth: Int) {
        self.elapsedDays = elapsedDays
        self.daysInMonth = daysInMonth
    }

    public var isFullMonth: Bool { elapsedDays == daysInMonth }

    /// floor(yen × elapsed ÷ days), nil on overflow.
    func scaled(_ yen: Int) -> Int? {
        BudgetMath.floorDivide(yen, times: elapsedDays, by: daysInMonth)
    }
}

// MARK: - Baseline

/// Spending in the baseline months: up to the last 3 months before the analysed month that
/// have at least one expense.
public struct SpendingBaseline: Sendable, Equatable {
    /// Most recent first; empty in limited history.
    public let months: [LedgerMonth]
    /// Totals over all baseline months, per category and per store.
    public let categories: [ExpenseCategory: Totals]
    public let stores: [String: Totals]

    public static let maximumMonths = 3

    public struct Totals: Sendable, Equatable {
        /// Sum over the baseline months, refunds included.
        public var yen: Int
        /// Visits: expenses with a positive total (a refund is not a visit).
        public var visits: Int
        /// Baseline months in which this category or store had any expense.
        public var monthsWithSpend: Int

        static let zero = Totals(yen: 0, visits: 0, monthsWithSpend: 0)
    }

    /// No closed month with an expense yet: comparisons are not available.
    public var isLimitedHistory: Bool { months.isEmpty }

    /// - Parameters:
    ///   - month: the month being analysed; only months before it count.
    ///   - history: saved expenses from earlier months (any range; others are ignored). The
    ///     caller decides how far back to read.
    /// Nil when a total does not fit in `Int`.
    public init?(before month: LedgerMonth, history: [some InsightItem]) {
        var byMonth: [LedgerMonth: [any InsightItem]] = [:]
        for item in history {
            guard let itemMonth = LedgerMonth(dayKey: item.dayKey), itemMonth < month else { continue }
            byMonth[itemMonth, default: []].append(item)
        }
        let months = Array(byMonth.keys.sorted(by: >).prefix(Self.maximumMonths))
        var categories: [ExpenseCategory: Totals] = [:]
        var stores: [String: Totals] = [:]
        for baselineMonth in months {
            let items = byMonth[baselineMonth] ?? []
            guard let monthCategories = Self.totals(items, key: { $0.category }),
                  let monthStores = Self.totals(items, key: { StoreKey.make($0.storeName) })
            else { return nil }
            guard Self.merge(monthCategories, into: &categories), Self.merge(monthStores, into: &stores) else { return nil }
        }
        self.months = months
        self.categories = categories
        self.stores = stores
    }

    /// Per-key totals for one month's items (each key with any item has `monthsWithSpend` 1).
    static func totals<Key: Hashable>(_ items: [any InsightItem], key: (any InsightItem) -> Key?) -> [Key: Totals]? {
        var result: [Key: Totals] = [:]
        for item in items {
            guard let k = key(item) else { continue }
            var t = result[k] ?? Totals(yen: 0, visits: 0, monthsWithSpend: 1)
            let (yen, overflow) = t.yen.addingReportingOverflow(item.totalYen)
            if overflow { return nil }
            t.yen = yen
            if item.totalYen > 0 { t.visits += 1 }
            result[k] = t
        }
        return result
    }

    private static func merge<Key: Hashable>(_ month: [Key: Totals], into all: inout [Key: Totals]) -> Bool {
        for (k, t) in month {
            var sum = all[k] ?? .zero
            let (yen, overflow) = sum.yen.addingReportingOverflow(t.yen)
            if overflow { return false }
            sum.yen = yen
            sum.visits += t.visits
            sum.monthsWithSpend += t.monthsWithSpend
            all[k] = sum
        }
        return true
    }

    /// The average month's spend scaled to `pace`, rounded down. Nil in limited history or
    /// on overflow.
    public func paceAdjustedYen(_ totals: Totals?, pace: MonthPace) -> Int? {
        guard !months.isEmpty else { return nil }
        let yen = totals?.yen ?? 0
        // floor(yen × e ÷ (n × D)), with n × D ≤ 3 × 31.
        return BudgetMath.floorDivide(yen, times: pace.elapsedDays, by: months.count * pace.daysInMonth)
    }

    /// The average month's visits scaled to `pace` (fractional). Nil in limited history.
    public func paceAdjustedVisits(_ totals: Totals?, pace: MonthPace) -> Double? {
        guard !months.isEmpty else { return nil }
        let visits = Double(totals?.visits ?? 0)
        return visits / Double(months.count) * Double(pace.elapsedDays) / Double(pace.daysInMonth)
    }
}

/// How stores are grouped: the saved name, trimmed. Unknown (empty) stores are left out of
/// store comparisons; their spending still counts for categories and the total.
enum StoreKey {
    static func make(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Comparison

/// The analysed month against its baseline, per category and per store.
public struct SpendingComparison: Sendable, Equatable {
    public let month: LedgerMonth
    public let pace: MonthPace
    public let baseline: SpendingBaseline
    /// Every category or store with spending this month or in the baseline, largest spend
    /// first (ties: category order, store name).
    public let categories: [Line<ExpenseCategory>]
    public let stores: [Line<String>]

    public struct Line<Key: Hashable & Sendable>: Sendable, Equatable {
        public let key: Key
        /// This month so far, refunds included.
        public let spentYen: Int
        /// Expenses with a positive total this month.
        public let visits: Int
        /// The baseline's average month scaled to the pace, rounded down. Nil in limited history.
        public let baselineYen: Int?
        /// The baseline's average visits scaled to the pace. Nil in limited history.
        public let baselineVisits: Double?
        /// Baseline months in which this key had any expense (0 means new this month).
        public let baselineMonthsWithSpend: Int

        /// spent − baseline: positive when above the usual pace. Nil in limited history or on overflow.
        public var differenceYen: Int? {
            guard let baselineYen else { return nil }
            let (d, overflow) = spentYen.subtractingReportingOverflow(baselineYen)
            return overflow ? nil : d
        }

        /// No spending in any baseline month (and there is a baseline to compare with).
        public var isNewThisMonth: Bool { baselineYen != nil && baselineMonthsWithSpend == 0 }
    }

    /// Nil for a future month, or when a total does not fit in `Int`.
    public init?(month: LedgerMonth, items: [some InsightItem], history: [some InsightItem],
                 now: Date, calendar: Calendar = .kakeibo) {
        guard let pace = MonthPace(month: month, now: now, calendar: calendar),
              let baseline = SpendingBaseline(before: month, history: history) else { return nil }
        let monthItems: [any InsightItem] = items.filter { LedgerMonth(dayKey: $0.dayKey) == month }
        guard let currentCategories = SpendingBaseline.totals(monthItems, key: { $0.category }),
              let currentStores = SpendingBaseline.totals(monthItems, key: { StoreKey.make($0.storeName) }),
              let categoryLines = Self.lines(currentCategories, baseline.categories, baseline, pace,
                                             order: { ExpenseCategory.allCases.firstIndex(of: $0)! < ExpenseCategory.allCases.firstIndex(of: $1)! }),
              let storeLines = Self.lines(currentStores, baseline.stores, baseline, pace, order: { $0 < $1 })
        else { return nil }
        self.month = month
        self.pace = pace
        self.baseline = baseline
        self.categories = categoryLines
        self.stores = storeLines
    }

    private static func lines<Key: Hashable & Sendable>(
        _ current: [Key: SpendingBaseline.Totals], _ past: [Key: SpendingBaseline.Totals],
        _ baseline: SpendingBaseline, _ pace: MonthPace, order: (Key, Key) -> Bool
    ) -> [Line<Key>]? {
        var result: [Line<Key>] = []
        for key in Set(current.keys).union(past.keys) {
            let now = current[key]
            let before = past[key]
            if !baseline.isLimitedHistory, baseline.paceAdjustedYen(before, pace: pace) == nil { return nil }
            result.append(Line(
                key: key,
                spentYen: now?.yen ?? 0,
                visits: now?.visits ?? 0,
                baselineYen: baseline.paceAdjustedYen(before, pace: pace),
                baselineVisits: baseline.paceAdjustedVisits(before, pace: pace),
                baselineMonthsWithSpend: before?.monthsWithSpend ?? 0
            ))
        }
        return result.sorted { a, b in a.spentYen != b.spentYen ? a.spentYen > b.spentYen : order(a.key, b.key) }
    }
}

// MARK: - Projection

public enum MonthProjection {
    /// floor(spent × days in month ÷ elapsed days): where spend ends up at the current pace.
    /// Nil before day 5, for any month but the current one, and on overflow.
    public static func projectedYen(month: LedgerMonth, spentYen: Int, now: Date, calendar: Calendar = .kakeibo) -> Int? {
        guard month == LedgerMonth(containing: now),
              let pace = MonthPace(month: month, now: now, calendar: calendar),
              pace.elapsedDays >= MonthPace.projectionStartDay else { return nil }
        return BudgetMath.floorDivide(spentYen, times: pace.daysInMonth, by: pace.elapsedDays)
    }
}

// MARK: - Insight

/// Whether a month gets an insight card, and the figures behind it.
public struct BudgetInsight: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        /// No budget, under pace, a future month, or figures out of range: no card.
        case none
        /// Current month, spend ≥ 80% of the budget or projected above it, and not over yet.
        case onPaceToOverspend
        /// Current month, spend above the budget.
        case overBudget
        /// A past month whose final spend was above its budget: read-only analysis.
        case closedMonthOverBudget
    }

    public let state: State
    /// B-01's figures for the month (S, B, R, weekly allowance).
    public let summary: BudgetSummary
    /// Month-end projection; current month from day 5 only.
    public let projectedYen: Int?
    /// The month against its baseline; nil for a future month or out-of-range totals.
    public let comparison: SpendingComparison?

    /// - Parameters:
    ///   - items: the month's saved expenses (the same ones the ledger lists).
    ///   - history: saved expenses from earlier months, for the baseline.
    ///   - now: the current moment; injected for tests.
    public init(month: LedgerMonth, budget: MonthlyBudget, items: [some InsightItem],
                history: [some InsightItem], now: Date, calendar: Calendar = .kakeibo) {
        let summary = BudgetSummary(month: month, budget: budget, items: items, now: now, calendar: calendar)
        self.summary = summary
        comparison = SpendingComparison(month: month, items: items, history: history, now: now, calendar: calendar)
        projectedYen = summary.spentYen.flatMap {
            MonthProjection.projectedYen(month: month, spentYen: $0, now: now, calendar: calendar)
        }
        state = Self.state(summary: summary, projectedYen: projectedYen, now: now)
    }

    static func state(summary: BudgetSummary, projectedYen: Int?, now: Date) -> State {
        guard summary.status == .active, let s = summary.spentYen, let b = summary.budgetYen else { return .none }
        let current = LedgerMonth(containing: now)
        if summary.month < current { return s > b ? .closedMonthOverBudget : .none }
        guard summary.month == current else { return .none }
        if s > b { return .overBudget }
        // Same 80% rule as the alerts (5·S ≥ 4·B), so the card and the 80% alert agree.
        let nearBudget = BudgetAlertPolicy.reachedThresholds(spentYen: s, budgetYen: b).contains(.eighty)
        let projectedOver = projectedYen.map { $0 > b } ?? false
        return nearBudget || projectedOver ? .onPaceToOverspend : .none
    }
}

// MARK: - Math

enum BudgetMath {
    /// floor(value × factor ÷ divisor) for factor ≥ 0 and divisor > 0, rounding down for
    /// negative values too. Nil on overflow.
    static func floorDivide(_ value: Int, times factor: Int, by divisor: Int) -> Int? {
        precondition(factor >= 0 && divisor > 0)
        // value = q·divisor + r, so value × factor ÷ divisor = q·factor + r·factor ÷ divisor.
        let q = value / divisor, r = value % divisor
        let (qf, overflow) = q.multipliedReportingOverflow(by: factor)
        guard !overflow else { return nil }
        let (rf, overflowR) = r.multipliedReportingOverflow(by: factor)
        guard !overflowR else { return nil }
        var part = rf / divisor
        if rf % divisor != 0, rf < 0 { part -= 1 }
        let (result, overflowSum) = qf.addingReportingOverflow(part)
        return overflowSum ? nil : result
    }
}
