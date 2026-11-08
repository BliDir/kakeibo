import Foundation

// What caused an overspend, and what to do about it (v1.2, BI-02).
//
// Drivers (Kakeibo iOS v1.2 Budget Insights spec; thresholds are proposed defaults):
// - Category increase: category spend − pace-adjusted baseline > ¥1,000 and spend > 120% of it.
// - Large one-off: one expense ≥ 10% of the budget, or ≥ 3× the category's median expense in
//   the baseline months. Impact = the expense − that median (0 when the category has none).
// - More visits: a store or category with ≥ 1.5× its pace-adjusted baseline visits and at
//   least 3 extra. Impact = whole extra visits × this month's average spend per visit.
// - New spending: a category or store with no expense in the baseline months and ≥ ¥3,000.
// - Limited history (no baseline month): the top 3 categories by share of this month's budget.
//
// No double counting: drivers are picked one at a time, largest impact first. Each pick
// claims its expenses, and the remaining candidates are worked out again from unclaimed
// expenses only. At most 3 drivers. Ties: impact, then kind (one-off, category increase, more
// visits, new spending), then category order or store name, then date.
//
// Suggestions are structured figures (no strings in Core); the app words them. Closed months
// get no rest-of-month figures.

/// A category or a store.
public enum InsightTarget: Sendable, Hashable {
    case category(ExpenseCategory)
    case store(String)
}

/// One cause of the overspend, with its yen impact and the figures for its suggestion.
public struct OverspendDriver: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case categoryIncrease
        case largeOneOff
        case moreVisits
        case newSpending
        /// Limited history: a category's share of this month's budget.
        case shareOfBudget
    }

    public let kind: Kind
    public let target: InsightTarget
    /// How much of the month's spend this driver explains, whole yen.
    public let impactYen: Int
    /// Positions in the analysed month's items (as passed in, after keeping only that month's
    /// expenses) that this driver claims. No expense belongs to two drivers.
    public let itemIndices: [Int]
    public let suggestion: Suggestion
}

/// What to show for a driver: the figures only.
public enum Suggestion: Sendable, Equatable {
    /// "Dining out is ¥12,400 above usual. Keeping it to ¥X for the rest of the month brings
    /// you back on track." `keepToYen` = the category's usual full-month spend minus what it
    /// has spent so far (at least 0); nil for a closed month.
    case categoryIncrease(ExpenseCategory, aboveUsualYen: Int, keepToYen: Int?)
    /// "14 convenience store visits vs 8 usual. 2 fewer visits saves about ¥1,600."
    /// `fewerVisits` = the extra visits still to come if this month's pace continues instead of
    /// the usual one; nil for a closed month or when none are left to save.
    case moreVisits(InsightTarget, visits: Int, usualVisits: Int, fewerVisits: Int?, savingYen: Int?)
    /// "One purchase of ¥38,000 at Y explains most of this month. If it was a one-off, your
    /// usual spending is on track." `onTrackWithout`: the month has no insight without it.
    case largeOneOff(ExpenseCategory, storeName: String, dayKey: String, amountYen: Int, typicalYen: Int,
                     onTrackWithout: Bool)
    /// "New this month: Z, ¥6,200."
    case newSpending(InsightTarget, amountYen: Int)
    /// Limited history: "Groceries is 34% of this month's budget." Percent rounded down; nil
    /// without a usable budget.
    case shareOfBudget(ExpenseCategory, spentYen: Int, percentOfBudget: Int?)
}

/// Drivers and suggestions for a month with an insight (BI-01's state).
public struct OverspendAnalysis: Sendable, Equatable {
    public let insight: BudgetInsight
    /// At most 3, largest impact first. Empty when the month has no insight.
    public let drivers: [OverspendDriver]
    /// No baseline month: drivers are the top categories by share of the budget, and the card
    /// says comparisons improve after the first full month.
    public let isLimitedHistory: Bool
    /// Sum of the drivers' impacts.
    public let explainedYen: Int
    /// What they explain: the overspend (S − B) when over budget, otherwise the spend above
    /// the pace-adjusted baseline; this month's spend in limited history. Nil when there is
    /// nothing positive to explain.
    public let basisYen: Int?
    /// explained ÷ basis, at most 1. Nil without a basis.
    public var explainedShare: Double? {
        guard let basisYen, basisYen > 0 else { return nil }
        return min(Double(explainedYen) / Double(basisYen), 1)
    }

    /// floor(max(B − S, 0) ÷ remaining days), today included: what keeps the month on budget.
    /// 0 when over budget; nil for a closed month or without a usable budget.
    public let dailyAmountYen: Int?
    /// B-01's "available this week" (0 when over budget); nil for a closed month.
    public let weeklyAmountYen: Int?
    /// Over budget: suggestions should focus on limiting further overspend.
    public var isOverBudget: Bool { insight.state == .overBudget || insight.state == .closedMonthOverBudget }

    // Proposed default thresholds (spec).
    public static let maximumDrivers = 3
    public static let categoryIncreaseMinimumYen = 1_000
    /// Spend must be above baseline × 6/5 (more than 20% above).
    static let categoryIncreaseRatio = (numerator: 6, denominator: 5)
    /// One expense ≥ budget × 1/10, or ≥ 3 × the category's baseline median.
    static let oneOffBudgetShare = (numerator: 1, denominator: 10)
    public static let oneOffMedianMultiple = 3
    /// Visits ≥ baseline × 3/2, and at least 3 extra.
    static let visitsRatio = (numerator: 3, denominator: 2)
    public static let minimumExtraVisits = 3
    public static let newSpendingMinimumYen = 3_000

    /// - Parameters:
    ///   - items: the month's saved expenses (the same ones the ledger lists).
    ///   - history: saved expenses from earlier months, for the baseline.
    public init(month: LedgerMonth, budget: MonthlyBudget, items: [some InsightItem],
                history: [some InsightItem], now: Date, calendar: Calendar = .kakeibo) {
        let insight = BudgetInsight(month: month, budget: budget, items: items, history: history, now: now, calendar: calendar)
        self.insight = insight
        let monthItems: [any InsightItem] = items.filter { LedgerMonth(dayKey: $0.dayKey) == month }
        let comparison = insight.comparison
        isLimitedHistory = comparison?.baseline.isLimitedHistory ?? true

        let isCurrent = insight.state == .onPaceToOverspend || insight.state == .overBudget
        let pace = comparison?.pace
        if isCurrent, let pace, let r = insight.summary.remainingYen {
            dailyAmountYen = Self.dailyAmount(remainingYen: r, pace: pace)
            weeklyAmountYen = insight.summary.weeklyAllowance?.yen
        } else {
            dailyAmountYen = nil
            weeklyAmountYen = nil
        }

        guard insight.state != .none, let comparison, let spent = insight.summary.spentYen,
              let budgetYen = insight.summary.budgetYen else {
            drivers = []
            explainedYen = 0
            basisYen = nil
            return
        }

        let context = DriverRules(month: month, budgetYen: budgetYen, spentYen: spent, items: monthItems,
                              history: history.map { $0 as any InsightItem }, comparison: comparison,
                              isCurrent: isCurrent, now: now, calendar: calendar)
        drivers = isLimitedHistory ? context.shareOfBudgetDrivers() : context.pickDrivers()
        explainedYen = drivers.reduce(0) { sum, d in sum.addingReportingOverflow(d.impactYen).overflow ? sum : sum + d.impactYen }

        if spent > budgetYen {
            basisYen = spent - budgetYen
        } else if isLimitedHistory {
            basisYen = spent > 0 ? spent : nil
        } else {
            let usual = comparison.categories.reduce(0) { $0 + ($1.baselineYen ?? 0) }
            let (above, overflow) = spent.subtractingReportingOverflow(usual)
            basisYen = !overflow && above > 0 ? above : nil
        }
    }
}

// MARK: - Shared rules (also used by the budget review, BI-03)

extension OverspendAnalysis {
    /// floor(max(R, 0) ÷ remaining days), today included.
    static func dailyAmount(remainingYen: Int, pace: MonthPace) -> Int {
        max(remainingYen, 0) / (pace.daysInMonth - pace.elapsedDays + 1)
    }

    /// The large one-off rule: ≥ 10% of the budget, or ≥ 3× the category's typical expense.
    static func isLargeOneOff(amountYen: Int, budgetYen: Int?, typicalYen: Int?) -> Bool {
        guard amountYen > 0 else { return false }
        let share = oneOffBudgetShare
        let forBudget = budgetYen.map { DriverRules.isAtLeast(amountYen, share.numerator, share.denominator, of: $0) } ?? false
        let forCategory = typicalYen.map { DriverRules.isAtLeast(amountYen, oneOffMedianMultiple, 1, of: $0) } ?? false
        return forBudget || forCategory
    }

    /// Median positive expense per category over `months`.
    static func typicalExpenses(_ history: [any InsightItem], in months: Set<LedgerMonth>) -> [ExpenseCategory: Int] {
        var amounts: [ExpenseCategory: [Int]] = [:]
        for item in history where item.totalYen > 0 {
            guard let m = LedgerMonth(dayKey: item.dayKey), months.contains(m) else { continue }
            amounts[item.category, default: []].append(item.totalYen)
        }
        return amounts.mapValues(DriverRules.median)
    }

    /// The drivers of `month` against its own baseline, whatever its insight state: what the
    /// budget review uses to tell an ongoing increase from a one-month blip. Empty in limited
    /// history (no baseline to compare with) or on overflow.
    static func drivers(month: LedgerMonth, budgetYen: Int, items: [any InsightItem], history: [any InsightItem],
                        now: Date, calendar: Calendar) -> [OverspendDriver] {
        let monthItems = items.filter { LedgerMonth(dayKey: $0.dayKey) == month }
        guard let comparison = SpendingComparison(month: month, items: monthItems.map(AnyInsightItem.init),
                                                  history: history.map(AnyInsightItem.init), now: now, calendar: calendar),
              !comparison.baseline.isLimitedHistory,
              let spent = MonthSpend.total(monthItems.map(AnyInsightItem.init)) else { return [] }
        let isCurrent = month == LedgerMonth(containing: now)
        return DriverRules(month: month, budgetYen: budgetYen, spentYen: spent, items: monthItems, history: history,
                       comparison: comparison, isCurrent: isCurrent, now: now, calendar: calendar).pickDrivers()
    }
}

/// A concrete wrapper, for passing `any InsightItem` arrays to the generic initializers.
struct AnyInsightItem: InsightItem {
    let base: any InsightItem
    init(_ base: any InsightItem) { self.base = base }
    var dayKey: String { base.dayKey }
    var totalYen: Int { base.totalYen }
    var tax10Yen: Int? { base.tax10Yen }
    var tax8Yen: Int? { base.tax8Yen }
    var category: ExpenseCategory { base.category }
    var storeName: String { base.storeName }
}

// MARK: - Picking drivers

struct DriverRules {
    let month: LedgerMonth
    let budgetYen: Int
    let spentYen: Int
    let items: [any InsightItem]
    let comparison: SpendingComparison
    let isCurrent: Bool
    let now: Date
    let calendar: Calendar
    /// Median positive expense per category in the baseline months.
    let medians: [ExpenseCategory: Int]

    init(month: LedgerMonth, budgetYen: Int, spentYen: Int, items: [any InsightItem], history: [any InsightItem],
         comparison: SpendingComparison, isCurrent: Bool, now: Date, calendar: Calendar) {
        self.month = month
        self.budgetYen = budgetYen
        self.spentYen = spentYen
        self.items = items
        self.comparison = comparison
        self.isCurrent = isCurrent
        self.now = now
        self.calendar = calendar
        medians = OverspendAnalysis.typicalExpenses(history, in: Set(comparison.baseline.months))
    }

    static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[mid] }
        // Rounded down, without overflow.
        let a = sorted[mid - 1], b = sorted[mid]
        return a / 2 + b / 2 + (a % 2 + b % 2) / 2
    }

    private var pace: MonthPace { comparison.pace }

    // MARK: Greedy pick

    func pickDrivers() -> [OverspendDriver] {
        var claimed = Set<Int>()
        var picked: [OverspendDriver] = []
        while picked.count < OverspendAnalysis.maximumDrivers {
            let free = items.indices.filter { !claimed.contains($0) }
            guard let best = candidates(among: free).min(by: Self.ranksBefore) else { break }
            picked.append(best)
            claimed.formUnion(best.itemIndices)
        }
        return picked
    }

    /// Larger impact first; then kind, target and date for a stable order.
    static func ranksBefore(_ a: OverspendDriver, _ b: OverspendDriver) -> Bool {
        if a.impactYen != b.impactYen { return a.impactYen > b.impactYen }
        if kindRank(a.kind) != kindRank(b.kind) { return kindRank(a.kind) < kindRank(b.kind) }
        if a.target != b.target { return targetRanksBefore(a.target, b.target) }
        return (a.itemIndices.first ?? 0) < (b.itemIndices.first ?? 0)
    }

    private static func kindRank(_ kind: OverspendDriver.Kind) -> Int {
        switch kind {
        case .largeOneOff: 0
        case .categoryIncrease: 1
        case .moreVisits: 2
        case .newSpending: 3
        case .shareOfBudget: 4
        }
    }

    private static func targetRanksBefore(_ a: InsightTarget, _ b: InsightTarget) -> Bool {
        switch (a, b) {
        case (.category(let x), .category(let y)):
            ExpenseCategory.allCases.firstIndex(of: x)! < ExpenseCategory.allCases.firstIndex(of: y)!
        case (.category, .store): true
        case (.store, .category): false
        case (.store(let x), .store(let y)): x < y
        }
    }

    // MARK: Candidates

    private func candidates(among free: [Int]) -> [OverspendDriver] {
        var result: [OverspendDriver] = []
        let byCategory = Dictionary(grouping: free) { items[$0].category }
        for line in comparison.categories {
            let indices = byCategory[line.key] ?? []
            guard !indices.isEmpty else { continue }
            let target = InsightTarget.category(line.key)
            if let d = categoryIncrease(line, indices) { result.append(d) }
            if let d = moreVisits(target, line.baselineVisits, line.baselineMonthsWithSpend, indices) { result.append(d) }
            if let d = newSpending(target, line.baselineMonthsWithSpend, indices) { result.append(d) }
        }
        let byStore = Dictionary(grouping: free.filter { StoreKey.make(items[$0].storeName) != nil }) {
            StoreKey.make(items[$0].storeName)!
        }
        for line in comparison.stores {
            let indices = byStore[line.key] ?? []
            guard !indices.isEmpty else { continue }
            let target = InsightTarget.store(line.key)
            if let d = moreVisits(target, line.baselineVisits, line.baselineMonthsWithSpend, indices) { result.append(d) }
            if let d = newSpending(target, line.baselineMonthsWithSpend, indices) { result.append(d) }
        }
        for index in free { if let d = largeOneOff(index) { result.append(d) } }
        return result
    }

    private func spent(_ indices: [Int]) -> Int? {
        var sum = 0
        for i in indices {
            let (next, overflow) = sum.addingReportingOverflow(items[i].totalYen)
            if overflow { return nil }
            sum = next
        }
        return sum
    }

    private func categoryIncrease(_ line: SpendingComparison.Line<ExpenseCategory>, _ indices: [Int]) -> OverspendDriver? {
        guard line.baselineMonthsWithSpend > 0, let baseline = line.baselineYen, let spent = spent(indices) else { return nil }
        let (above, overflow) = spent.subtractingReportingOverflow(baseline)
        let ratio = OverspendAnalysis.categoryIncreaseRatio
        guard !overflow, above > OverspendAnalysis.categoryIncreaseMinimumYen,
              Self.isAbove(spent, ratio.numerator, ratio.denominator, of: baseline) else { return nil }
        var keepTo: Int?
        if isCurrent, let totals = comparison.baseline.categories[line.key] {
            // The usual full month for this category, less what it has spent this month.
            let usualMonth = BudgetMath.floorDivide(totals.yen, times: 1, by: comparison.baseline.months.count) ?? 0
            keepTo = max(usualMonth - line.spentYen, 0)
        }
        return OverspendDriver(kind: .categoryIncrease, target: .category(line.key), impactYen: above, itemIndices: indices,
                               suggestion: .categoryIncrease(line.key, aboveUsualYen: above, keepToYen: keepTo))
    }

    private func moreVisits(_ target: InsightTarget, _ baselineVisits: Double?, _ monthsWithSpend: Int,
                            _ indices: [Int]) -> OverspendDriver? {
        guard monthsWithSpend > 0, let usual = baselineVisits, usual > 0 else { return nil }
        let visitIndices = indices.filter { items[$0].totalYen > 0 }
        let visits = visitIndices.count
        let ratio = OverspendAnalysis.visitsRatio
        guard Double(visits) * Double(ratio.denominator) >= usual * Double(ratio.numerator) else { return nil }
        let extra = Int((Double(visits) - usual).rounded(.down))
        guard extra >= OverspendAnalysis.minimumExtraVisits, let visitSpend = spent(visitIndices) else { return nil }
        let perVisit = visitSpend / visits
        let (impact, overflow) = perVisit.multipliedReportingOverflow(by: extra)
        guard !overflow, impact > 0 else { return nil }

        var fewer: Int?
        var saving: Int?
        if isCurrent {
            // Extra visits still to come if this month's pace continues instead of the usual one.
            let daysAfterToday = pace.daysInMonth - pace.elapsedDays
            let usualPerDay = usual / Double(pace.elapsedDays)
            let currentPerDay = Double(visits) / Double(pace.elapsedDays)
            let ahead = Int(((currentPerDay - usualPerDay) * Double(daysAfterToday)).rounded(.down))
            if ahead >= 1 {
                fewer = ahead
                saving = perVisit.multipliedReportingOverflow(by: ahead).overflow ? nil : perVisit * ahead
            }
        }
        return OverspendDriver(kind: .moreVisits, target: target, impactYen: impact, itemIndices: indices,
                               suggestion: .moreVisits(target, visits: visits, usualVisits: Int(usual.rounded()),
                                                       fewerVisits: fewer, savingYen: saving))
    }

    private func newSpending(_ target: InsightTarget, _ monthsWithSpend: Int, _ indices: [Int]) -> OverspendDriver? {
        guard monthsWithSpend == 0, let spent = spent(indices), spent >= OverspendAnalysis.newSpendingMinimumYen else { return nil }
        return OverspendDriver(kind: .newSpending, target: target, impactYen: spent, itemIndices: indices,
                               suggestion: .newSpending(target, amountYen: spent))
    }

    private func largeOneOff(_ index: Int) -> OverspendDriver? {
        let item = items[index]
        let amount = item.totalYen
        guard amount > 0 else { return nil }
        let typical = medians[item.category]
        guard OverspendAnalysis.isLargeOneOff(amountYen: amount, budgetYen: budgetYen, typicalYen: typical) else { return nil }
        let impact = amount - (typical ?? 0)
        guard impact > 0 else { return nil }
        return OverspendDriver(
            kind: .largeOneOff, target: .category(item.category), impactYen: impact, itemIndices: [index],
            suggestion: .largeOneOff(item.category, storeName: item.storeName, dayKey: item.dayKey, amountYen: amount,
                                     typicalYen: typical ?? 0, onTrackWithout: onTrack(without: amount))
        )
    }

    /// The month would have no insight without this expense.
    private func onTrack(without amount: Int) -> Bool {
        let (rest, overflow) = spentYen.subtractingReportingOverflow(amount)
        guard !overflow else { return false }
        let summary = BudgetSummary(month: month, budget: .yen(budgetYen), spentYen: rest, now: now, calendar: calendar)
        let projected = MonthProjection.projectedYen(month: month, spentYen: rest, now: now, calendar: calendar)
        return BudgetInsight.state(summary: summary, projectedYen: projected, now: now) == .none
    }

    // MARK: Limited history

    /// The top 3 categories by share of this month's budget (largest spend first).
    func shareOfBudgetDrivers() -> [OverspendDriver] {
        comparison.categories
            .filter { $0.spentYen > 0 }
            .prefix(OverspendAnalysis.maximumDrivers)
            .map { line in
                let indices = items.indices.filter { items[$0].category == line.key }
                let percent = BudgetMath.floorDivide(line.spentYen, times: 100, by: budgetYen)
                return OverspendDriver(kind: .shareOfBudget, target: .category(line.key), impactYen: line.spentYen,
                                       itemIndices: indices,
                                       suggestion: .shareOfBudget(line.key, spentYen: line.spentYen, percentOfBudget: percent))
            }
    }

    // MARK: Exact comparisons

    /// value > base × n ÷ d, compared as value × d > base × n (falls back to Double on overflow).
    static func isAbove(_ value: Int, _ n: Int, _ d: Int, of base: Int) -> Bool {
        let (l, o1) = value.multipliedReportingOverflow(by: d)
        let (r, o2) = base.multipliedReportingOverflow(by: n)
        if o1 || o2 { return Double(value) * Double(d) > Double(base) * Double(n) }
        return l > r
    }

    /// value ≥ base × n ÷ d.
    static func isAtLeast(_ value: Int, _ n: Int, _ d: Int, of base: Int) -> Bool {
        let (l, o1) = value.multipliedReportingOverflow(by: d)
        let (r, o2) = base.multipliedReportingOverflow(by: n)
        if o1 || o2 { return Double(value) * Double(d) >= Double(base) * Double(n) }
        return l >= r
    }
}
