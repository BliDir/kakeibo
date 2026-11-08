import Foundation
import Testing
@testable import KakeiboCore

private struct Item: InsightItem {
    var dayKey: String
    var totalYen: Int
    var category: ExpenseCategory = .groceries
    var storeName: String = "西友"
    var tax10Yen: Int? = nil
    var tax8Yen: Int? = nil
}

private func tokyo(_ dayKey: String, _ hour: Int = 12) -> Date {
    let p = dayKey.split(separator: "-").map { Int($0)! }
    return Calendar.kakeibo.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: hour))!
}

private func month(_ key: String) -> LedgerMonth {
    let p = key.split(separator: "-").map { Int($0)! }
    return LedgerMonth(year: p[0], month: p[1])
}

private let november = month("2026-11")
/// Day 15 of 30: the pace factor is exactly 1/2.
private let midNovember = tokyo("2026-11-15")

/// A month of expenses: `groceries` trips of ¥8,000 at 西友 and `dining` visits of ¥2,500 at
/// 喫茶ポエム, spread over the first 28 days, plus any `extra`.
private func spending(_ key: String, groceries: Int, dining: Int, extra: [Item] = []) -> [Item] {
    let g = (0..<groceries).map { Item(dayKey: String(format: "\(key)-%02d", 1 + $0 * 27 / max(groceries, 1)), totalYen: 8_000) }
    let d = (0..<dining).map {
        Item(dayKey: String(format: "\(key)-%02d", 1 + $0 * 27 / max(dining, 1)), totalYen: 2_500, category: .dining, storeName: "喫茶ポエム")
    }
    return g + d + extra
}

/// June to October at the usual ¥116,000: 12 grocery trips (¥96,000) and 8 dining visits (¥20,000).
private func steady(_ months: [String] = ["2026-06", "2026-07", "2026-08", "2026-09", "2026-10"]) -> [Item] {
    months.flatMap { spending($0, groceries: 12, dining: 8) }
}

private func review(_ items: [Item], budget: Int, history: [Item], pastBudgets: [String: Int] = [:],
                    month m: LedgerMonth = november, now: Date = midNovember) -> BudgetReview {
    BudgetReview(month: m, budget: .yen(budget), items: items, history: history,
                 pastBudgets: Dictionary(uniqueKeysWithValues: pastBudgets.map { (month($0.key), MonthlyBudget.yen($0.value)) }),
                 now: now)
}

// MARK: - Suggested budget

@Suite struct SuggestedBudgetTests {
    @Test func notEnoughHistoryWithFewerThanTwoMonths() {
        #expect(review([], budget: 120_000, history: []).suggested == .notEnoughHistory)
        #expect(review([], budget: 120_000, history: steady(["2026-10"])).suggested == .notEnoughHistory)
    }

    @Test func twoMonthsUseTheMidpoint() {
        // 116,000 and 136,000: midpoint 126,000.
        let history = steady(["2026-09"]) + spending("2026-10", groceries: 12, dining: 16)
        #expect(review([], budget: 120_000, history: history).suggested == .yen(126_000))
    }

    @Test func threeMonthsUseTheMiddleOne() {
        let history = spending("2026-08", groceries: 10, dining: 8)      // 100,000
            + spending("2026-09", groceries: 13, dining: 8)              // 124,000
            + spending("2026-10", groceries: 12, dining: 9)              // 118,500
        #expect(review([], budget: 120_000, history: history).suggested == .yen(119_000), "118,500 rounded up")
    }

    /// Only the 3 most recent months with an expense; empty months are skipped.
    @Test func atMostThreeMonths() {
        let history = spending("2026-05", groceries: 30, dining: 0) + steady(["2026-07", "2026-08", "2026-10"])
        #expect(review([], budget: 120_000, history: history).suggested == .yen(116_000))
    }

    @Test(arguments: [([45_000], 45_000), ([45_001], 46_000), ([41_000, 44_500], 43_000), ([40_000, 40_001], 41_000),
                      ([1, 2, 3], 1_000), ([-5_000, 2_000], 1_000), ([0], 1_000)])
    func roundsUpToAThousand(totals: [Int], expected: Int) {
        #expect(BudgetReview.roundUp(median: totals.sorted()) == expected)
    }

    @Test func neverAboveTheLargestBudget() {
        #expect(BudgetReview.roundUp(median: [Int.max - 1, Int.max]) == 999_999_000)
        #expect(BudgetReview.roundUp(median: [999_999_500]) == 999_999_000)
    }

    /// A ¥60,000 purchase in September (above 10% of the budget, and the category has no
    /// other expense) is left out of that month's total.
    @Test func largeOneOffsAreRemoved() {
        let tv = Item(dayKey: "2026-09-20", totalYen: 60_000, category: .shopping, storeName: "ヨドバシ")
        let history = spending("2026-08", groceries: 12, dining: 8)                  // 116,000
            + spending("2026-09", groceries: 12, dining: 8, extra: [tv])              // 176,000, or 116,000 without the TV
            + spending("2026-10", groceries: 15, dining: 8)                           // 140,000
        // Kept, the median would be 140,000.
        #expect(review([], budget: 150_000, history: history).suggested == .yen(116_000))
    }

    /// The 10% rule uses each month's own budget; without one, the current budget.
    @Test func eachMonthsOwnBudgetDecidesTheTenPercentRule() {
        let fridge = Item(dayKey: "2026-09-20", totalYen: 20_000, category: .shopping, storeName: "ヨドバシ")
        let history = spending("2026-08", groceries: 10, dining: 8)                   // 100,000
            + spending("2026-09", groceries: 12, dining: 8, extra: [fridge])          // 136,000, or 116,000 without
            + spending("2026-10", groceries: 15, dining: 8)                           // 140,000
        // Against the current ¥150,000, ¥20,000 is a one-off (≥ 15,000): removed.
        #expect(review([], budget: 150_000, history: history).suggested == .yen(116_000))
        // September's own ¥300,000 makes it ordinary (< 30,000): kept.
        #expect(review([], budget: 150_000, history: history, pastBudgets: ["2026-09": 300_000]).suggested == .yen(136_000))
    }

    /// ≥ 3× the category's other expenses, even under 10% of the budget.
    @Test func outliersByTheCategoryMedianAreRemoved() {
        let feast = Item(dayKey: "2026-09-21", totalYen: 7_500, category: .dining, storeName: "喫茶ポエム")
        let history = spending("2026-08", groceries: 12, dining: 8)                   // 116,000
            + spending("2026-09", groceries: 13, dining: 8, extra: [feast])           // 131,500, or 124,000 without
            + spending("2026-10", groceries: 15, dining: 8)                           // 140,000
        #expect(review([], budget: 300_000, history: history).suggested == .yen(124_000))
    }

    /// An ordinary trip that is 10% of a small budget is not an outlier.
    @Test func ordinaryExpensesAreNotRemoved() {
        // ¥8,000 trips are above 10% of ¥50,000 but equal to the usual trip.
        #expect(review([], budget: 50_000, history: steady(["2026-08", "2026-09", "2026-10"])).suggested == .yen(116_000))
    }
}

// MARK: - Recommendation

@Suite struct BudgetRecommendationTests {
    /// Over budget mostly because of one large purchase: keep the budget.
    @Test func oneOffOverspendKeeps() {
        // November: 4 grocery trips (32,000), a ¥70,000 grocery purchase, 4 dining visits (10,000) = 112,000 > 100,000.
        let big = Item(dayKey: "2026-11-10", totalYen: 70_000)
        let items = spending("2026-11", groceries: 4, dining: 4, extra: [big]).map { fixDay($0) }
        let result = review(items, budget: 100_000, history: steady())
        #expect(result.analysis.insight.state == .overBudget)
        #expect(result.analysis.drivers.first?.kind == .largeOneOff)
        #expect(result.recommendation == .keep(.oneOffOverspend))
    }

    /// Dining has been above its usual level for three months in a row and the month is over
    /// budget: raise to the suggested budget.
    @Test func ongoingIncreaseRaises() {
        let history = steady(["2026-06", "2026-07", "2026-08"])
            + spending("2026-09", groceries: 12, dining: 16) + spending("2026-10", groceries: 12, dining: 16)
        let items = spending("2026-11", groceries: 14, dining: 16).map { fixDay($0) }   // 152,000
        let result = review(items, budget: 130_000, history: history)
        #expect(result.analysis.insight.state == .overBudget)
        #expect(result.suggested == .yen(136_000))       // median of 136,000, 136,000, 116,000
        #expect(result.recommendation == .raise(toYen: 136_000, category: .dining))
    }

    @Test func noRaiseWhenTheSuggestionIsNotHigher() {
        let history = steady(["2026-06", "2026-07", "2026-08"])
            + spending("2026-09", groceries: 12, dining: 16) + spending("2026-10", groceries: 12, dining: 16)
        let items = spending("2026-11", groceries: 18, dining: 16).map { fixDay($0) }   // 184,000
        let result = review(items, budget: 140_000, history: history)
        #expect(result.analysis.insight.state == .overBudget)
        #expect(result.recommendation == .keep(.noChangeNeeded))
    }

    @Test func noRaiseForAOneMonthIncrease() {
        let items = spending("2026-11", groceries: 14, dining: 16).map { fixDay($0) }
        let result = review(items, budget: 100_000, history: steady())
        #expect(result.analysis.insight.state == .overBudget)
        #expect(result.suggested == .yen(116_000))
        #expect(result.recommendation == .keep(.noChangeNeeded), "dining is a driver this month only")
    }

    /// Well under budget for the last 3 closed months: lower to the suggested budget.
    @Test func budgetTooHighLowers() {
        let budgets = ["2026-08": 200_000, "2026-09": 200_000, "2026-10": 200_000]   // 116,000 is 58%
        let result = review(spending("2026-11", groceries: 4, dining: 2).map { fixDay($0) }, budget: 200_000,
                            history: steady(), pastBudgets: budgets)
        #expect(result.analysis.insight.state == .none)
        #expect(result.recommendation == .lower(toYen: 116_000))
    }

    /// "Below 70%" is strict, in every month: October's ¥165,000 budget puts 70% at ¥115,500,
    /// and its ¥116,000 spend is not below that.
    @Test func notWellUnderInOneMonthIsNotTooHigh() {
        let budgets = ["2026-08": 200_000, "2026-09": 200_000, "2026-10": 165_000]
        #expect(review([], budget: 200_000, history: steady(), pastBudgets: budgets).recommendation == .keep(.noChangeNeeded))
        // October at ¥166,000 (70% = 116,200): all three well under, so lower.
        let under = budgets.merging(["2026-10": 166_000]) { _, new in new }
        #expect(review([], budget: 200_000, history: steady(), pastBudgets: under).recommendation == .lower(toYen: 116_000))
    }

    @Test func aMonthWithoutABudgetIsNotTooHigh() {
        let result = review([], budget: 200_000, history: steady(), pastBudgets: ["2026-09": 200_000, "2026-10": 200_000])
        #expect(result.recommendation == .keep(.noChangeNeeded))
    }

    @Test func noLowerWithoutEnoughHistory() {
        let budgets = ["2026-08": 200_000, "2026-09": 200_000, "2026-10": 200_000]
        let result = review([], budget: 200_000, history: steady(["2026-10"]), pastBudgets: budgets)
        #expect(result.suggested == .notEnoughHistory)
        #expect(result.recommendation == .keep(.noChangeNeeded))
    }

    @Test func otherwiseKeepWithTheSuggestionForReference() {
        let result = review(spending("2026-11", groceries: 6, dining: 4).map { fixDay($0) }, budget: 120_000, history: steady())
        #expect(result.recommendation == .keep(.noChangeNeeded))
        #expect(result.suggested == .yen(116_000))
    }

    @Test func zeroHistoryKeeps() {
        let result = review(spending("2026-11", groceries: 14, dining: 16).map { fixDay($0) }, budget: 100_000, history: [])
        #expect(result.suggested == .notEnoughHistory)
        #expect(result.analysis.isLimitedHistory)
        #expect(result.recommendation == .keep(.noChangeNeeded))
    }
}

/// November expenses are spread over 28 days by `spending`; keep them on or before the 15th
/// so they have happened by `midNovember`.
private func fixDay(_ item: Item) -> Item {
    var copy = item
    if let day = Int(item.dayKey.suffix(2)), day > 15 {
        copy.dayKey = String(item.dayKey.prefix(8)) + String(format: "%02d", 1 + day % 15)
    }
    return copy
}

// MARK: - Previews

@Suite struct BudgetPreviewTests {
    private let items = [Item(dayKey: "2026-11-03", totalYen: 90_000)]

    /// Every figure is B-01's for the chosen amount.
    @Test(arguments: [BudgetReview.Choice.keep, .thisMonthOnly, .fromThisMonthOn])
    func previewsMatchB01(choice: BudgetReview.Choice) throws {
        let result = review(items, budget: 100_000, history: steady())
        let amount = choice == .keep ? 100_000 : 130_000
        let preview = try #require(result.preview(choice, newBudgetYen: 130_000, now: midNovember))
        let b01 = BudgetSummary(month: november, budget: .yen(amount), spentYen: 90_000, now: midNovember)
        #expect(preview.budgetYen == amount)
        #expect(preview.remainingYen == b01.remainingYen)
        #expect(preview.weeklyAmountYen == b01.weeklyAllowance?.yen)
        // 16 days left, today included.
        #expect(preview.dailyAmountYen == max(b01.remainingYen!, 0) / 16)
        #expect(preview.appliesToFutureMonths == (choice == .fromThisMonthOn))
    }

    @Test func changeDefaultsToTheSuggestedBudget() throws {
        let result = review(items, budget: 100_000, history: steady())
        let preview = try #require(result.preview(.thisMonthOnly, now: midNovember))
        #expect(preview.budgetYen == 116_000)
        #expect(preview.remainingYen == 26_000)
        #expect(preview.dailyAmountYen == 1_625)
    }

    @Test func stillOverBudgetMeansZeroAmounts() throws {
        let result = review(items, budget: 80_000, history: steady())
        let keep = try #require(result.preview(.keep, now: midNovember))
        #expect(keep.remainingYen == -10_000)
        #expect(keep.dailyAmountYen == 0)
        #expect(keep.weeklyAmountYen == 0)
    }

    @Test func invalidAmountsHaveNoPreview() {
        let result = review(items, budget: 100_000, history: steady())
        #expect(result.preview(.thisMonthOnly, newBudgetYen: 0, now: midNovember) == nil)
        #expect(result.preview(.fromThisMonthOn, newBudgetYen: 1_000_000_000, now: midNovember) == nil)
        // No suggestion and no amount: nothing to preview.
        let noHistory = review(items, budget: 100_000, history: [])
        #expect(noHistory.preview(.thisMonthOnly, now: midNovember) == nil)
        #expect(noHistory.preview(.keep, now: midNovember) != nil)
    }

    /// A closed month's review is read-only: only "keep", with no rest-of-month figures.
    @Test func closedMonthsCannotBeChanged() throws {
        let october = month("2026-10")
        let history = steady(["2026-07", "2026-08", "2026-09"])
        let items = spending("2026-10", groceries: 14, dining: 16)
        let result = review(items, budget: 120_000, history: history, month: october)
        #expect(result.analysis.insight.state == .closedMonthOverBudget)
        #expect(!result.isEditable)
        #expect(result.preview(.thisMonthOnly, newBudgetYen: 150_000, now: midNovember) == nil)
        #expect(result.preview(.fromThisMonthOn, newBudgetYen: 150_000, now: midNovember) == nil)
        let keep = try #require(result.preview(.keep, now: midNovember))
        #expect(keep.dailyAmountYen == nil)
        #expect(keep.weeklyAmountYen == nil)
    }
}
