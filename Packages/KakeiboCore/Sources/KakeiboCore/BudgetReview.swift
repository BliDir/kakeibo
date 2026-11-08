import Foundation

// Suggested budget and budget review rules (v1.2, BI-03).
//
// Suggested budget (spec): the median of the baseline months' totals, with flagged large
// one-offs removed, rounded up to ¥1,000. Needs at least 2 baseline months.
//
// Recommendation (spec; the first rule that applies):
// 1. One-off overspend: large one-off drivers explain ≥ 50% of the overspend → keep.
// 2. Ongoing increase: over budget, the same category is a driver in ≥ 2 of the last 3 months,
//    and the suggested budget is above the current one → raise to the suggested budget.
// 3. Budget too high: spend < 70% of the budget in each of the last 3 closed months (and the
//    suggested budget is below the current one) → lower to the suggested budget.
// 4. Otherwise keep, showing the suggested budget for reference.
//
// Previews use B-01 (`BudgetSummary`) unchanged. Only the current month can be changed; a
// closed month's review is read-only.

/// What the review suggests as a budget.
public enum SuggestedBudget: Sendable, Equatable {
    /// Fewer than 2 baseline months: "Not enough history yet"; only a manual edit is offered.
    case notEnoughHistory
    case yen(Int)

    public var yen: Int? {
        if case .yen(let yen) = self { yen } else { nil }
    }
}

public struct BudgetReview: Sendable, Equatable {
    public enum Recommendation: Sendable, Equatable {
        /// Keep the current budget.
        case keep(KeepReason)
        /// Raise to the suggested budget (an ongoing increase in `category`).
        case raise(toYen: Int, category: ExpenseCategory)
        /// Lower to the suggested budget (well under budget for the last 3 closed months).
        case lower(toYen: Int)
    }

    public enum KeepReason: Sendable, Equatable {
        /// Large one-offs explain at least half of the overspend.
        case oneOffOverspend
        /// Nothing calls for a change; the suggested budget is shown for reference.
        case noChangeNeeded
    }

    /// The three choices on the review sheet.
    public enum Choice: Sendable, Equatable, CaseIterable {
        case keep
        case thisMonthOnly
        /// Also saves the amount for future months (B-04's "Use this amount for future months").
        case fromThisMonthOn
    }

    public let month: LedgerMonth
    public let currentBudget: MonthlyBudget
    public let suggested: SuggestedBudget
    public let recommendation: Recommendation
    /// Only the current Tokyo month can be changed from the review.
    public let isEditable: Bool
    /// The drivers and figures the review is based on (BI-02).
    public let analysis: OverspendAnalysis

    /// Share of the overspend one-offs must explain to keep the budget: 1/2.
    static let oneOffKeepShare = (numerator: 1, denominator: 2)
    /// "Budget too high": spend below 7/10 of the budget in each closed month checked.
    static let tooHighShare = (numerator: 7, denominator: 10)
    public static let monthsChecked = 3
    public static let minimumBaselineMonths = 2
    public static let roundingYen = 1_000

    /// - Parameters:
    ///   - month: the month under review (normally the current one).
    ///   - budget: its budget.
    ///   - items: its saved expenses.
    ///   - history: saved expenses from earlier months (the same as for `BudgetInsight`).
    ///   - pastBudgets: budgets of earlier months as stored (B-02); months left out had none.
    public init(month: LedgerMonth, budget: MonthlyBudget, items: [some InsightItem], history: [some InsightItem],
                pastBudgets: [LedgerMonth: MonthlyBudget], now: Date, calendar: Calendar = .kakeibo) {
        let analysis = OverspendAnalysis(month: month, budget: budget, items: items, history: history, now: now, calendar: calendar)
        self.month = month
        self.currentBudget = budget
        self.analysis = analysis
        isEditable = month == LedgerMonth(containing: now)

        let past: [any InsightItem] = history.map { $0 as any InsightItem }
        let suggested = Self.suggestedBudget(baseline: analysis.insight.comparison?.baseline, history: past,
                                             pastBudgets: pastBudgets, fallbackBudget: budget.yen)
        self.suggested = suggested
        recommendation = Self.recommend(month: month, budget: budget, suggested: suggested, analysis: analysis,
                                        items: items.map { $0 as any InsightItem }, history: past,
                                        pastBudgets: pastBudgets, now: now, calendar: calendar)
    }

    // MARK: Suggested budget

    static func suggestedBudget(baseline: SpendingBaseline?, history: [any InsightItem],
                                pastBudgets: [LedgerMonth: MonthlyBudget], fallbackBudget: Int?) -> SuggestedBudget {
        guard let baseline, baseline.months.count >= minimumBaselineMonths else { return .notEnoughHistory }
        let months = Set(baseline.months)
        let inBaseline = history.filter { LedgerMonth(dayKey: $0.dayKey).map(months.contains) ?? false }
        // Each category's positive expenses, to compare an expense with the others.
        var amounts: [ExpenseCategory: [Int]] = [:]
        for item in inBaseline where item.totalYen > 0 { amounts[item.category, default: []].append(item.totalYen) }
        var totals: [Int] = []
        for m in baseline.months {
            // A month's own budget decides the 10% rule; without one, the current budget.
            let budgetYen = pastBudgets[m]?.yen ?? fallbackBudget
            var total = 0
            for item in inBaseline where LedgerMonth(dayKey: item.dayKey) == m {
                // Flagged as in BI-02: large by the one-off rule and above the typical expense
                // of the category's other expenses (so an ordinary trip that happens to be 10% of
                // a small budget stays, and a category's only expense can still be flagged).
                var others = amounts[item.category] ?? []
                if let i = others.firstIndex(of: item.totalYen) { others.remove(at: i) }
                let typicalYen = others.isEmpty ? nil : DriverRules.median(others)
                if OverspendAnalysis.isLargeOneOff(amountYen: item.totalYen, budgetYen: budgetYen, typicalYen: typicalYen),
                   item.totalYen > (typicalYen ?? 0) { continue }
                let (next, overflow) = total.addingReportingOverflow(item.totalYen)
                guard !overflow else { return .notEnoughHistory }
                total = next
            }
            totals.append(total)
        }
        return .yen(roundUp(median: totals.sorted()))
    }

    /// The median rounded up to ¥1,000, between ¥1,000 and the largest budget allowed.
    /// With an even count the median is the midpoint, which can be half a yen; rounding up
    /// to ¥1,000 handles it exactly (ceil((a + b) ÷ 2,000) × 1,000).
    static func roundUp(median sorted: [Int]) -> Int {
        let mid = sorted.count / 2
        let (twice, overflow) = sorted.count % 2 == 1
            ? sorted[mid].multipliedReportingOverflow(by: 2)
            : sorted[mid - 1].addingReportingOverflow(sorted[mid])
        let maximum = MonthlyBudget.maximumYen / roundingYen * roundingYen
        guard !overflow else { return sorted[mid] > 0 ? maximum : roundingYen }
        guard twice > 0 else { return roundingYen }
        let step = roundingYen * 2
        let (rounded, overflowRounded) = ((twice + step - 1) / step).multipliedReportingOverflow(by: roundingYen)
        guard !overflowRounded else { return maximum }
        return min(max(rounded, roundingYen), maximum)
    }

    // MARK: Recommendation

    static func recommend(month: LedgerMonth, budget: MonthlyBudget, suggested: SuggestedBudget,
                          analysis: OverspendAnalysis, items: [any InsightItem], history: [any InsightItem],
                          pastBudgets: [LedgerMonth: MonthlyBudget], now: Date, calendar: Calendar) -> Recommendation {
        guard let current = budget.yen, let spent = analysis.insight.summary.spentYen else { return .keep(.noChangeNeeded) }

        // 1. One-off overspend.
        if let basis = analysis.basisYen, basis > 0 {
            let oneOffs = analysis.drivers.filter { $0.kind == .largeOneOff }.reduce(0) { $0 + $1.impactYen }
            let share = oneOffKeepShare
            if oneOffs > 0, DriverRules.isAtLeast(oneOffs, share.numerator, share.denominator, of: basis) {
                return .keep(.oneOffOverspend)
            }
        }

        // 2. Ongoing increase.
        if spent > current, let suggestedYen = suggested.yen, suggestedYen > current,
           let category = repeatedDriverCategory(month: month, currentBudget: current, analysis: analysis, items: items,
                                                 history: history, pastBudgets: pastBudgets, now: now, calendar: calendar) {
            return .raise(toYen: suggestedYen, category: category)
        }

        // 3. Budget too high.
        if let suggestedYen = suggested.yen, suggestedYen < current,
           wellUnderBudget(before: month, history: history, pastBudgets: pastBudgets) {
            return .lower(toYen: suggestedYen)
        }

        // 4. Otherwise.
        return .keep(.noChangeNeeded)
    }

    /// A category that is a driver in at least 2 of the last 3 months (this month and the two
    /// before), each month judged against its own baseline. Most months first, then the
    /// driver order of this month, then category order.
    static func repeatedDriverCategory(month: LedgerMonth, currentBudget: Int, analysis: OverspendAnalysis,
                                       items: [any InsightItem], history: [any InsightItem],
                                       pastBudgets: [LedgerMonth: MonthlyBudget], now: Date, calendar: Calendar) -> ExpenseCategory? {
        var months: [Set<ExpenseCategory>] = [categories(of: analysis.drivers)]
        var earlier = month
        for _ in 1..<monthsChecked {
            earlier = earlier.previous
            let budgetYen = pastBudgets[earlier]?.yen ?? currentBudget
            let before = history.filter { LedgerMonth(dayKey: $0.dayKey).map { $0 < earlier } ?? false }
            let drivers = OverspendAnalysis.drivers(month: earlier, budgetYen: budgetYen, items: history, history: before,
                                                    now: now, calendar: calendar)
            months.append(categories(of: drivers))
        }
        var counts: [ExpenseCategory: Int] = [:]
        for set in months { for c in set { counts[c, default: 0] += 1 } }
        let thisMonthOrder = analysis.drivers.compactMap { driver -> ExpenseCategory? in
            if case .category(let c) = driver.target { c } else { nil }
        }
        return counts.filter { $0.value >= 2 }.keys.sorted { a, b in
            if counts[a]! != counts[b]! { return counts[a]! > counts[b]! }
            let ia = thisMonthOrder.firstIndex(of: a) ?? .max, ib = thisMonthOrder.firstIndex(of: b) ?? .max
            if ia != ib { return ia < ib }
            return ExpenseCategory.allCases.firstIndex(of: a)! < ExpenseCategory.allCases.firstIndex(of: b)!
        }.first
    }

    /// Categories a month's drivers point at (store drivers are not counted).
    private static func categories(of drivers: [OverspendDriver]) -> Set<ExpenseCategory> {
        Set(drivers.compactMap { driver in
            guard driver.kind != .shareOfBudget, case .category(let c) = driver.target else { return nil }
            return c
        })
    }

    /// Each of the 3 months before `month` had a valid budget and spend below 70% of it.
    static func wellUnderBudget(before month: LedgerMonth, history: [any InsightItem],
                                pastBudgets: [LedgerMonth: MonthlyBudget]) -> Bool {
        var m = month
        for _ in 0..<monthsChecked {
            m = m.previous
            guard let b = pastBudgets[m]?.yen,
                  let s = MonthSpend.total(history.filter { LedgerMonth(dayKey: $0.dayKey) == m }.map(AnyInsightItem.init))
            else { return false }
            let share = tooHighShare
            // s < b × 7/10, compared as s × 10 < b × 7.
            if DriverRules.isAtLeast(s, share.numerator, share.denominator, of: b) { return false }
        }
        return true
    }

    // MARK: Previews

    /// What one choice would mean for this month, using B-01 rules. `newBudgetYen` is the
    /// amount for the change choices (defaults to the suggested budget); keep ignores it.
    /// Nil when the month cannot be edited (except keep), or the amount is not a valid budget.
    public func preview(_ choice: Choice, newBudgetYen: Int? = nil, now: Date, calendar: Calendar = .kakeibo) -> BudgetPreview? {
        let budget: MonthlyBudget
        switch choice {
        case .keep:
            budget = currentBudget
        case .thisMonthOnly, .fromThisMonthOn:
            guard isEditable, let yen = newBudgetYen ?? suggested.yen else { return nil }
            budget = MonthlyBudget.validated(yen)
        }
        guard let yen = budget.yen else { return nil }
        let summary = BudgetSummary(month: month, budget: budget, spentYen: analysis.insight.summary.spentYen,
                                    now: now, calendar: calendar)
        guard summary.status == .active, let remaining = summary.remainingYen else { return nil }
        let pace = MonthPace(month: month, now: now, calendar: calendar)
        let daily = isEditable ? pace.map { OverspendAnalysis.dailyAmount(remainingYen: remaining, pace: $0) } : nil
        return BudgetPreview(choice: choice, budgetYen: yen, remainingYen: remaining, dailyAmountYen: daily,
                             weeklyAmountYen: summary.weeklyAllowance?.yen,
                             appliesToFutureMonths: choice == .fromThisMonthOn)
    }
}

/// One choice's effect on this month, shown before the user confirms.
public struct BudgetPreview: Sendable, Equatable {
    public let choice: BudgetReview.Choice
    public let budgetYen: Int
    /// R = B − S, signed (negative when still over).
    public let remainingYen: Int
    /// floor(max(R, 0) ÷ remaining days); nil for a closed month.
    public let dailyAmountYen: Int?
    /// B-01's "available this week"; nil for a closed month.
    public let weeklyAmountYen: Int?
    /// "From this month on": the amount is also used for future months (B-04).
    public let appliesToFutureMonths: Bool
}
