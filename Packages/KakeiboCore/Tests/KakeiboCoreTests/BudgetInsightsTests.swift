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

/// A moment in Tokyo: `yyyy-MM-dd` at hour:minute.
private func tokyo(_ dayKey: String, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    let p = dayKey.split(separator: "-").map { Int($0)! }
    return Calendar.kakeibo.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: hour, minute: minute))!
}

private func month(_ key: String) -> LedgerMonth {
    let p = key.split(separator: "-").map { Int($0)! }
    return LedgerMonth(year: p[0], month: p[1])
}

private func item(_ day: String, _ yen: Int, _ category: ExpenseCategory = .groceries, store: String = "西友") -> Item {
    Item(dayKey: day, totalYen: yen, category: category, storeName: store)
}

// MARK: - Baseline months

@Suite struct SpendingBaselineTests {
    private let november = month("2026-11")

    @Test func noHistoryIsLimitedHistory() throws {
        let baseline = try #require(SpendingBaseline(before: november, history: [Item]()))
        #expect(baseline.isLimitedHistory)
        #expect(baseline.months.isEmpty)
        #expect(baseline.paceAdjustedYen(nil, pace: MonthPace(elapsedDays: 10, daysInMonth: 30)) == nil)
        #expect(baseline.paceAdjustedVisits(nil, pace: MonthPace(elapsedDays: 10, daysInMonth: 30)) == nil)
    }

    @Test(arguments: [1, 2, 3])
    func usesUpToThreeMonths(count: Int) throws {
        let history = ["2026-10-05", "2026-09-05", "2026-08-05"].prefix(count).map { item($0, 1_000) }
        let baseline = try #require(SpendingBaseline(before: november, history: history))
        #expect(baseline.months.count == count)
        #expect(!baseline.isLimitedHistory)
    }

    @Test func neverMoreThanThreeMonthsMostRecentFirst() throws {
        let history = ["2026-10-05", "2026-09-05", "2026-08-05", "2026-07-05", "2026-06-05"].map { item($0, 1_000) }
        let baseline = try #require(SpendingBaseline(before: november, history: history))
        #expect(baseline.months == [month("2026-10"), month("2026-09"), month("2026-08")])
    }

    /// Months with no expense are skipped: the three most recent months that have one count.
    @Test func emptyMonthsAreSkipped() throws {
        let history = [item("2026-10-02", 1_000), item("2026-07-10", 2_000), item("2026-04-30", 3_000), item("2026-03-01", 9_000)]
        let baseline = try #require(SpendingBaseline(before: november, history: history))
        #expect(baseline.months == [month("2026-10"), month("2026-07"), month("2026-04")])
        #expect(baseline.categories[.groceries]?.yen == 6_000)
    }

    /// The analysed month and later months are never part of its own baseline.
    @Test func onlyMonthsBeforeTheAnalysedMonthCount() throws {
        let history = [item("2026-11-01", 5_000), item("2026-12-01", 5_000), item("2026-10-31", 1_000)]
        let baseline = try #require(SpendingBaseline(before: november, history: history))
        #expect(baseline.months == [month("2026-10")])
        #expect(baseline.categories[.groceries]?.yen == 1_000)
    }

    /// A refund is an expense (the month counts) and lowers the total, but it is not a visit.
    @Test func refundsCountAsSpendNotVisits() throws {
        let history = [item("2026-10-02", 3_000), item("2026-10-09", -500)]
        let baseline = try #require(SpendingBaseline(before: november, history: history))
        #expect(baseline.categories[.groceries] == .init(yen: 2_500, visits: 1, monthsWithSpend: 1))
        // A month with only a refund still has an expense, so it is a baseline month.
        let refundOnly = try #require(SpendingBaseline(before: november, history: [item("2026-09-03", -800)]))
        #expect(refundOnly.months == [month("2026-09")])
    }

    @Test func storesAreGroupedByTrimmedNameAndUnknownStoresLeftOut() throws {
        let history = [item("2026-10-02", 500, store: "ローソン"), item("2026-10-03", 300, store: " ローソン "),
                       item("2026-10-04", 900, store: "")]
        let baseline = try #require(SpendingBaseline(before: november, history: history))
        #expect(baseline.stores == ["ローソン": .init(yen: 800, visits: 2, monthsWithSpend: 1)])
        #expect(baseline.categories[.groceries]?.yen == 1_700, "unknown stores still count for the category")
    }

    @Test func overflowingHistoryIsNil() {
        let history = [item("2026-10-02", Int.max), item("2026-10-03", 1)]
        #expect(SpendingBaseline(before: november, history: history) == nil)
    }
}

// MARK: - Pace and comparison

@Suite struct SpendingComparisonTests {
    @Test func currentMonthPaceIsTodayInclusive() throws {
        let pace = try #require(MonthPace(month: month("2026-11"), now: tokyo("2026-11-10")))
        #expect(pace == MonthPace(elapsedDays: 10, daysInMonth: 30))
        #expect(!pace.isFullMonth)
    }

    /// Month lengths, including leap years (2028) and the century rule (2000 was a leap year).
    @Test(arguments: [("2026-02", 28), ("2028-02", 29), ("2000-02", 29), ("2026-04", 30), ("2026-01", 31)])
    func closedMonthsAreFullMonths(key: String, days: Int) throws {
        let pace = try #require(MonthPace(month: month(key), now: tokyo("2029-01-15")))
        #expect(pace == MonthPace(elapsedDays: days, daysInMonth: days))
        #expect(pace.isFullMonth)
    }

    @Test func futureMonthHasNoPaceOrComparison() {
        #expect(MonthPace(month: month("2026-12"), now: tokyo("2026-11-30")) == nil)
        #expect(SpendingComparison(month: month("2026-12"), items: [Item](), history: [Item](), now: tokyo("2026-11-30")) == nil)
    }

    /// Average of the baseline months × elapsed ÷ days in month; a month without the category counts as 0.
    @Test func paceAdjustedBaselinePerCategory() throws {
        let history = [
            item("2026-10-05", 30_000, .dining), item("2026-09-05", 60_000, .dining),
            item("2026-08-05", 1_000, .groceries),                       // August: no dining
        ]
        let items = [item("2026-11-02", 12_000, .dining), item("2026-11-08", 4_000, .dining)]
        let comparison = try #require(SpendingComparison(month: month("2026-11"), items: items, history: history,
                                                         now: tokyo("2026-11-10")))
        let dining = try #require(comparison.categories.first { $0.key == .dining })
        // (30,000 + 60,000 + 0) ÷ 3 = 30,000 a month; × 10 ÷ 30 = 10,000 so far.
        #expect(dining.baselineYen == 10_000)
        #expect(dining.spentYen == 16_000)
        #expect(dining.differenceYen == 6_000)
        #expect(dining.visits == 2)
        #expect(dining.baselineVisits == 2.0 / 3.0 * 10.0 / 30.0)
        #expect(dining.baselineMonthsWithSpend == 2)
        #expect(!dining.isNewThisMonth)
    }

    @Test func storesAreComparedToo() throws {
        let history = (1...8).map { item(String(format: "2026-10-%02d", $0), 500, store: "ローソン") }
        let items = (1...7).map { item(String(format: "2026-11-%02d", $0), 600, store: "ローソン") }
        let comparison = try #require(SpendingComparison(month: month("2026-11"), items: items, history: history,
                                                         now: tokyo("2026-11-15")))
        let lawson = try #require(comparison.stores.first { $0.key == "ローソン" })
        #expect(lawson.visits == 7)
        #expect(lawson.baselineVisits == 4.0)                // 8 visits × 15 ÷ 30
        #expect(lawson.baselineYen == 2_000)                 // 4,000 × 15 ÷ 30
        #expect(lawson.spentYen == 4_200)
    }

    @Test func closedMonthComparesFullMonthToFullMonth() throws {
        let history = [item("2026-09-10", 20_000, .dining), item("2026-08-10", 40_000, .dining)]
        let items = [item("2026-10-10", 45_000, .dining)]
        let comparison = try #require(SpendingComparison(month: month("2026-10"), items: items, history: history,
                                                         now: tokyo("2026-11-20")))
        #expect(comparison.pace.isFullMonth)
        #expect(comparison.categories.first { $0.key == .dining }?.baselineYen == 30_000)
    }

    @Test func spendingNotSeenInTheBaselineIsNew() throws {
        let history = [item("2026-10-05", 5_000, .groceries)]
        let items = [item("2026-11-03", 6_200, .shopping, store: "ヨドバシカメラ")]
        let comparison = try #require(SpendingComparison(month: month("2026-11"), items: items, history: history,
                                                         now: tokyo("2026-11-10")))
        #expect(comparison.categories.first { $0.key == .shopping }?.isNewThisMonth == true)
        #expect(comparison.stores.first { $0.key == "ヨドバシカメラ" }?.isNewThisMonth == true)
        // A baseline category with nothing this month is still listed, at 0.
        let groceries = try #require(comparison.categories.first { $0.key == .groceries })
        #expect(groceries.spentYen == 0)
        #expect(groceries.isNewThisMonth == false)
    }

    @Test func limitedHistoryHasNoBaselineFigures() throws {
        let comparison = try #require(SpendingComparison(month: month("2026-11"), items: [item("2026-11-03", 6_000)],
                                                         history: [Item](), now: tokyo("2026-11-10")))
        #expect(comparison.baseline.isLimitedHistory)
        let line = try #require(comparison.categories.first)
        #expect(line.baselineYen == nil)
        #expect(line.differenceYen == nil)
        #expect(!line.isNewThisMonth, "nothing is new without a baseline to compare with")
    }

    /// Lines run largest spend first; ties in the category order.
    @Test func linesAreOrderedBySpend() throws {
        let items = [item("2026-11-01", 1_000, .dining), item("2026-11-02", 5_000, .groceries), item("2026-11-03", 1_000, .transport)]
        let comparison = try #require(SpendingComparison(month: month("2026-11"), items: items, history: [Item](),
                                                         now: tokyo("2026-11-10")))
        let order = comparison.categories.map(\.key)
        #expect(order.first == .groceries)
        let tied = order.filter { $0 == .dining || $0 == .transport }
        #expect(tied == ExpenseCategory.allCases.filter { $0 == .dining || $0 == .transport })
    }

    /// Items outside the analysed month (by Tokyo dayKey) are ignored.
    @Test func onlyTheMonthsItemsCount() throws {
        let items = [item("2026-11-01", 1_000), item("2026-10-31", 9_000)]
        let comparison = try #require(SpendingComparison(month: month("2026-11"), items: items, history: [Item](),
                                                         now: tokyo("2026-11-10")))
        #expect(comparison.categories.first?.spentYen == 1_000)
    }
}

// MARK: - Projection

@Suite struct MonthProjectionTests {
    @Test(arguments: [1, 2, 3, 4])
    func noProjectionBeforeDayFive(day: Int) {
        #expect(MonthProjection.projectedYen(month: month("2026-11"), spentYen: 10_000,
                                             now: tokyo(String(format: "2026-11-%02d", day))) == nil)
    }

    @Test func projectsFromDayFive() {
        // 10,000 ÷ 5 × 30 = 60,000.
        #expect(MonthProjection.projectedYen(month: month("2026-11"), spentYen: 10_000, now: tokyo("2026-11-05")) == 60_000)
        // Rounded down: 10,000 ÷ 7 × 30 = 42,857.14…
        #expect(MonthProjection.projectedYen(month: month("2026-11"), spentYen: 10_000, now: tokyo("2026-11-07")) == 42_857)
    }

    @Test(arguments: [("2026-02-14", 28, 56_000), ("2028-02-14", 29, 58_000), ("2026-01-14", 31, 62_000)])
    func usesTheMonthsLength(day: String, days: Int, expected: Int) {
        // 28,000 spent by the 14th.
        #expect(MonthProjection.projectedYen(month: LedgerMonth(dayKey: day)!, spentYen: 28_000, now: tokyo(day)) == expected)
    }

    @Test func onlyForTheCurrentMonth() {
        #expect(MonthProjection.projectedYen(month: month("2026-10"), spentYen: 10_000, now: tokyo("2026-11-20")) == nil)
        #expect(MonthProjection.projectedYen(month: month("2026-12"), spentYen: 10_000, now: tokyo("2026-11-20")) == nil)
    }

    @Test func refundsCanMakeItNegative() {
        #expect(MonthProjection.projectedYen(month: month("2026-11"), spentYen: -1_000, now: tokyo("2026-11-07")) == -4_286)
    }

    /// 00:30 on 1 December in Tokyo is still 30 November in UTC: it is December, day 1.
    @Test func tokyoMonthBoundaries() {
        let justAfterMidnight = tokyo("2026-12-01", 0, 30)
        #expect(MonthProjection.projectedYen(month: month("2026-12"), spentYen: 5_000, now: justAfterMidnight) == nil)
        #expect(MonthProjection.projectedYen(month: month("2026-11"), spentYen: 5_000, now: justAfterMidnight) == nil)
        #expect(MonthPace(month: month("2026-11"), now: justAfterMidnight)?.isFullMonth == true)
        // 23:59 on 30 November in Tokyo: November, day 30.
        #expect(MonthProjection.projectedYen(month: month("2026-11"), spentYen: 30_000, now: tokyo("2026-11-30", 23, 59)) == 30_000)
    }

    @Test func overflowIsNil() {
        #expect(MonthProjection.projectedYen(month: month("2026-11"), spentYen: Int.max, now: tokyo("2026-11-05")) == nil)
    }
}

// MARK: - Insight state

@Suite struct BudgetInsightStateTests {
    private let now = tokyo("2026-11-10")   // day 10 of 30

    private func insight(spent: Int, budget: MonthlyBudget = .yen(100_000), month key: String = "2026-11",
                         now: Date? = nil, history: [Item] = []) -> BudgetInsight {
        let m = month(key)
        let items = spent == 0 ? [] : [item(m.key + "-01", spent)]
        return BudgetInsight(month: m, budget: budget, items: items, history: history, now: now ?? self.now)
    }

    @Test func underPaceHasNoInsight() {
        // 20,000 by day 10 projects 60,000.
        #expect(insight(spent: 20_000).state == .none)
    }

    @Test func eightyPercentIsOnPace() {
        #expect(insight(spent: 80_000).state == .onPaceToOverspend)
        #expect(insight(spent: 79_999, now: tokyo("2026-11-28")).state == .none, "below 80% and projected under")
    }

    @Test func projectedAboveBudgetIsOnPace() {
        // 40,000 by day 10 projects 120,000 > 100,000.
        #expect(insight(spent: 40_000).state == .onPaceToOverspend)
        // Day 15 of 30: 50,000 projects exactly the budget, which is not above it; 50,001 is.
        let midMonth = tokyo("2026-11-15")
        #expect(insight(spent: 50_000, now: midMonth).projectedYen == 100_000)
        #expect(insight(spent: 50_000, now: midMonth).state == .none)
        #expect(insight(spent: 50_001, now: midMonth).state == .onPaceToOverspend)
    }

    @Test(arguments: [1, 2, 3, 4])
    func noProjectionBasedInsightBeforeDayFive(day: Int) {
        let early = tokyo(String(format: "2026-11-%02d", day))
        #expect(insight(spent: 40_000, now: early).state == .none)
        #expect(insight(spent: 40_000, now: early).projectedYen == nil)
        #expect(insight(spent: 85_000, now: early).state == .onPaceToOverspend, "80% still counts")
    }

    @Test func exactlyTheBudgetIsOnPaceNotOver() {
        #expect(insight(spent: 100_000).state == .onPaceToOverspend)
        #expect(insight(spent: 100_001).state == .overBudget)
    }

    @Test func closedMonthOverBudget() {
        let past = insight(spent: 120_000, month: "2026-10")
        #expect(past.state == .closedMonthOverBudget)
        #expect(past.projectedYen == nil)
        #expect(past.summary.weeklyAllowance == nil)
        // A closed month at or under budget, even above 80%, has no insight.
        #expect(insight(spent: 95_000, month: "2026-10").state == .none)
        #expect(insight(spent: 100_000, month: "2026-10").state == .none)
    }

    @Test func futureMonthHasNoInsight() {
        let future = insight(spent: 150_000, month: "2026-12")
        #expect(future.state == .none)
        #expect(future.comparison == nil)
    }

    @Test(arguments: [MonthlyBudget.unset, .invalid(.notPositive), .yen(0), .yen(-5)])
    func noUsableBudgetHasNoInsight(budget: MonthlyBudget) {
        let result = insight(spent: 150_000, budget: budget)
        #expect(result.state == .none)
        // The comparison is still worked out; only the card's state needs a budget.
        #expect(result.comparison != nil)
    }

    /// Spend is B-01's S: refunds included, so a refund can bring the month back under.
    @Test func refundsFollowB01() {
        let m = month("2026-11")
        let items = [item("2026-11-02", 105_000), item("2026-11-08", -10_000)]
        let result = BudgetInsight(month: m, budget: .yen(100_000), items: items, history: [Item](), now: now)
        #expect(result.summary.spentYen == 95_000)
        #expect(result.summary.spentYen == MonthSpend.total(items))
        #expect(result.state == .onPaceToOverspend)
    }

    /// The card's 80% matches the 80% alert exactly (5·S ≥ 4·B in integers).
    @Test(arguments: [(79_999, false), (80_000, true), (80_001, true)])
    func eightyPercentMatchesTheAlertRule(spent: Int, near: Bool) {
        let late = tokyo("2026-11-30")   // projection = spend: only the 80% rule can trigger
        let alert = BudgetAlertPolicy.reachedThresholds(spentYen: spent, budgetYen: 100_000).contains(.eighty)
        #expect(alert == near)
        #expect((insight(spent: spent, now: late).state == .onPaceToOverspend) == near)
    }

    @Test func insightCarriesTheComparison() throws {
        let history = [item("2026-10-05", 30_000)]
        let result = insight(spent: 40_000, history: history)
        let comparison = try #require(result.comparison)
        #expect(comparison.baseline.months == [month("2026-10")])
        #expect(comparison.categories.first?.baselineYen == 10_000)
        #expect(result.projectedYen == 120_000)
    }

    @Test func outOfRangeSpendHasNoInsight() {
        let m = month("2026-11")
        let items = [item("2026-11-01", Int.max), item("2026-11-02", 1)]
        let result = BudgetInsight(month: m, budget: .yen(100_000), items: items, history: [Item](), now: now)
        #expect(result.state == .none)
        #expect(result.comparison == nil)
        #expect(result.projectedYen == nil)
    }
}

@Suite struct BudgetMathTests {
    @Test func floorDivideRoundsDown() {
        #expect(BudgetMath.floorDivide(10, times: 1, by: 3) == 3)
        #expect(BudgetMath.floorDivide(-10, times: 1, by: 3) == -4)
        #expect(BudgetMath.floorDivide(-9, times: 1, by: 3) == -3)
        #expect(BudgetMath.floorDivide(0, times: 7, by: 3) == 0)
        #expect(BudgetMath.floorDivide(999_999_999 * 3, times: 31, by: 93) == 999_999_999)
        #expect(BudgetMath.floorDivide(Int.max, times: 2, by: 1) == nil)
    }
}
