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

private func item(_ day: String, _ yen: Int, _ category: ExpenseCategory = .groceries, store: String = "西友") -> Item {
    Item(dayKey: day, totalYen: yen, category: category, storeName: store)
}

private let november = LedgerMonth(year: 2026, month: 11)
/// Day 15 of 30: the pace factor is exactly 1/2.
private let midNovember = tokyo("2026-11-15")

/// Three baseline months (August to October) with the same steady spending:
/// groceries ¥30,000 a month at 西友 in 3 visits, and dining ¥10,000 a month in 4 visits
/// of ¥2,500 at 喫茶ポエム.
private func steadyHistory() -> [Item] {
    var items: [Item] = []
    for m in ["2026-08", "2026-09", "2026-10"] {
        for d in ["05", "12", "19"] { items.append(item("\(m)-\(d)", 10_000, .groceries, store: "西友")) }
        for d in ["03", "10", "17", "24"] { items.append(item("\(m)-\(d)", 2_500, .dining, store: "喫茶ポエム")) }
    }
    return items
}

/// Groceries at the usual mid-month pace (¥15,000 in 2 visits at 西友): never a driver.
private func usualGroceries() -> [Item] {
    [item("2026-11-05", 7_500), item("2026-11-12", 7_500)]
}

private func analysis(_ items: [Item], budget: Int = 50_000, history: [Item] = steadyHistory(),
                      month: LedgerMonth = november, now: Date = midNovember) -> OverspendAnalysis {
    OverspendAnalysis(month: month, budget: .yen(budget), items: items, history: history, now: now)
}

// MARK: - Each driver type

@Suite struct DriverTypeTests {
    /// Dining: usual ¥5,000 by mid-month; ¥9,000 spent in 3 visits (fewer than usual, so not "more visits").
    @Test func categoryIncrease() throws {
        let items = [item("2026-11-02", 3_000, .dining, store: "喫茶ポエム"), item("2026-11-08", 3_000, .dining, store: "喫茶ポエム"),
                     item("2026-11-14", 3_000, .dining, store: "喫茶ポエム")] + usualGroceries()
        let result = analysis(items, budget: 45_000)        // 24,000 by day 15 projects 48,000
        let driver = try #require(result.drivers.first { $0.kind == .categoryIncrease })
        #expect(driver.target == .category(.dining))
        #expect(driver.impactYen == 4_000)                  // 9,000 − 5,000
        // Usual full month ¥10,000, ¥9,000 spent: keep the rest of the month to ¥1,000.
        #expect(driver.suggestion == .categoryIncrease(.dining, aboveUsualYen: 4_000, keepToYen: 1_000))
    }

    @Test func categoryIncreaseNeedsMoreThan1000AndMoreThan20Percent() {
        // Groceries well above usual put the month on pace; the budget is high enough that
        // the dining expense is under 10% of it (not a one-off).
        let groceries = [item("2026-11-05", 12_500), item("2026-11-12", 12_500)]
        // ¥6,000 vs ¥5,000 usual: exactly 20% above and exactly ¥1,000 over: neither is "more than".
        let edge = analysis([item("2026-11-02", 6_000, .dining, store: "喫茶ポエム")] + groceries, budget: 61_000)
        #expect(edge.insight.state == .onPaceToOverspend)
        #expect(!edge.drivers.contains { $0.kind == .categoryIncrease && $0.target == .category(.dining) })
        // ¥6,001: more than both.
        let over = analysis([item("2026-11-02", 6_001, .dining, store: "喫茶ポエム")] + groceries, budget: 61_000)
        #expect(over.drivers.contains { $0.kind == .categoryIncrease && $0.target == .category(.dining) })
    }

    /// ≥ 10% of the budget. Impact = the expense − the category's baseline median (¥10,000).
    @Test func largeOneOffAgainstTheBudget() throws {
        let items = [item("2026-11-03", 38_000, .groceries, store: "西友"), item("2026-11-04", 5_000)]
        let result = analysis(items, budget: 40_000)
        let driver = try #require(result.drivers.first)
        #expect(driver.kind == .largeOneOff)
        #expect(driver.impactYen == 28_000)
        #expect(driver.itemIndices == [0])
        #expect(driver.suggestion == .largeOneOff(.groceries, storeName: "西友", dayKey: "2026-11-03",
                                                  amountYen: 38_000, typicalYen: 10_000, onTrackWithout: true))
    }

    /// ≥ 3× the category's median, even when below 10% of the budget.
    @Test func largeOneOffAgainstTheCategoryMedian() throws {
        // Dining median ¥2,500; ¥7,500 is exactly 3× (and under 10% of ¥100,000).
        let items = [item("2026-11-06", 7_500, .dining, store: "喫茶ポエム"), item("2026-11-07", 80_000)]
        let result = analysis(items, budget: 100_000)
        let driver = try #require(result.drivers.first { $0.kind == .largeOneOff && $0.target == .category(.dining) })
        #expect(driver.target == .category(.dining))
        #expect(driver.impactYen == 5_000)
        // ¥7,499 is under 3×: not a one-off.
        let below = analysis([item("2026-11-06", 7_499, .dining, store: "喫茶ポエム"), item("2026-11-07", 80_000)], budget: 100_000)
        #expect(!below.drivers.contains { $0.kind == .largeOneOff && $0.target == .category(.dining) })
    }

    @Test func oneOffThatStillLeavesTheMonthOverIsNotOnTrack() throws {
        let items = [item("2026-11-03", 10_000, .shopping, store: "ニトリ")] + (1...12).map { item(String(format: "2026-11-%02d", $0), 4_000) }
        let result = analysis(items, budget: 40_000)
        let oneOff = try #require(result.drivers.first { $0.kind == .largeOneOff })
        guard case .largeOneOff(_, _, _, _, _, let onTrack) = oneOff.suggestion else { Issue.record("wrong suggestion"); return }
        #expect(!onTrack)
    }

    /// 喫茶ポエム: 4 visits a month = 2 by mid-month; 7 visits now = 5 extra, ≥ 1.5×.
    @Test func moreVisits() throws {
        let items = (1...7).map { item(String(format: "2026-11-%02d", $0 * 2), 1_000, .dining, store: "喫茶ポエム") }
            + [item("2026-11-01", 40_000)]
        let result = analysis(items, budget: 45_000)
        let driver = try #require(result.drivers.first { $0.kind == .moreVisits })
        // The category and the store both qualify; one claims the visits, so only one is shown.
        #expect(result.drivers.filter { $0.kind == .moreVisits }.count == 1)
        #expect(driver.impactYen == 5_000)                  // 5 extra × ¥1,000 a visit
        // Pace: 7 visits in 15 days vs 2 usual: (7 − 2) ÷ 15 × 15 days left = 5 fewer, saving ¥5,000.
        guard case .moreVisits(_, let visits, let usual, let fewer, let saving) = driver.suggestion else {
            Issue.record("wrong suggestion"); return
        }
        #expect(visits == 7)
        #expect(usual == 2)
        #expect(fewer == 5)
        #expect(saving == 5_000)
    }

    @Test func moreVisitsNeedsThreeExtraAndOneAndAHalfTimes() {
        // 4 visits vs 2 usual: 2× but only 2 extra.
        let items = (1...4).map { item(String(format: "2026-11-%02d", $0), 1_000, .dining, store: "喫茶ポエム") }
            + [item("2026-11-05", 40_000)]
        #expect(!analysis(items).drivers.contains { $0.kind == .moreVisits })
    }

    /// No spend in any baseline month and ≥ ¥3,000.
    @Test func newSpending() throws {
        // Budget ¥63,000, so ¥6,200 is under 10% of it (otherwise it would also be a one-off,
        // which ranks first on a tie).
        let groceries = [item("2026-11-05", 12_750), item("2026-11-12", 12_750)]
        let items = [item("2026-11-04", 6_200, .kids, store: "西松屋")] + groceries
        let result = analysis(items, budget: 63_000)
        let driver = try #require(result.drivers.first { $0.kind == .newSpending })
        // The category and the store are both new; the category ranks first on a tie.
        #expect(driver.target == .category(.kids))
        #expect(driver.suggestion == .newSpending(.category(.kids), amountYen: 6_200))
        #expect(result.drivers.filter { $0.kind == .newSpending }.count == 1, "the store's expense is already claimed")
        // ¥2,999 is too small.
        let small = analysis([item("2026-11-04", 2_999, .kids, store: "西松屋")] + groceries, budget: 63_000)
        #expect(!small.drivers.contains { $0.kind == .newSpending })
    }

    /// A big purchase at a store never seen before: "new spending" (impact = the whole amount)
    /// beats "large one-off" (impact = amount − usual expense), as largest impact wins.
    @Test func bigPurchaseAtANewStoreIsNewSpending() throws {
        let result = analysis([item("2026-11-03", 38_000, .groceries, store: "コストコ"), item("2026-11-04", 5_000)], budget: 40_000)
        #expect(result.drivers.first?.suggestion == .newSpending(.store("コストコ"), amountYen: 38_000))
        #expect(!result.drivers.contains { $0.itemIndices.contains(0) && $0.kind == .largeOneOff })
    }

    @Test func newStoreInAKnownCategory() throws {
        let items = [item("2026-11-04", 4_000, .groceries, store: "成城石井"), item("2026-11-05", 40_000)]
        let result = analysis(items, budget: 42_000)
        #expect(result.drivers.contains { $0.suggestion == .newSpending(.store("成城石井"), amountYen: 4_000) })
    }
}

// MARK: - Picking, ties and double counting

@Suite struct DriverPickingTests {
    /// A one-off inside a category increase: groceries are ¥39,000 above usual (54,000 − 15,000),
    /// more than the one-off's ¥28,000, so the category increase claims both expenses and the
    /// one-off is not counted again.
    @Test func noExpenseCountsTwice() throws {
        let items = [item("2026-11-03", 38_000, .groceries, store: "西友"), item("2026-11-04", 16_000)]
        let result = analysis(items, budget: 40_000)
        let all = result.drivers.flatMap(\.itemIndices)
        #expect(all.count == Set(all).count)
        let first = try #require(result.drivers.first)
        #expect(first.kind == .categoryIncrease)
        #expect(first.impactYen == 39_000)
        #expect(first.itemIndices == [0, 1])
        #expect(!result.drivers.contains { $0.kind == .largeOneOff })
    }

    /// When the one-off is the bigger explanation, it claims its expense first and the
    /// category is judged on what is left.
    @Test func oneOffFirstThenTheRestOfItsCategory() throws {
        // One-off: 38,000 − 10,000 = 28,000. Whole category: 42,000 − 15,000 = 27,000.
        let items = [item("2026-11-03", 38_000, .groceries, store: "西友"), item("2026-11-04", 4_000)]
        let result = analysis(items, budget: 40_000)
        let first = try #require(result.drivers.first)
        #expect(first.kind == .largeOneOff)
        #expect(first.itemIndices == [0])
        // What is left of groceries (¥4,000) is under the usual ¥15,000: no increase.
        #expect(!result.drivers.contains { $0.kind == .categoryIncrease })
    }

    @Test func atMostThreeLargestFirst() {
        let items = [
            item("2026-11-02", 20_000, .shopping, store: "ニトリ"),        // new, ¥20,000
            item("2026-11-03", 9_000, .kids, store: "西松屋"),              // new, ¥9,000
            item("2026-11-04", 6_000, .health, store: "マツキヨ"),          // new, ¥6,000
            item("2026-11-05", 4_000, .utilities, store: "東京電力"),       // new, ¥4,000
        ]
        let result = analysis(items, budget: 30_000)
        #expect(result.drivers.count == 3)
        #expect(result.drivers.map(\.impactYen) == result.drivers.map(\.impactYen).sorted(by: >))
        #expect(!result.drivers.contains { $0.target == .category(.utilities) || $0.target == .store("東京電力") })
    }

    /// Equal impacts: the kind order decides (one-off before new spending), then category order.
    @Test func tiesAreStable() {
        let items = [item("2026-11-02", 5_000, .kids, store: "西松屋"), item("2026-11-03", 5_000, .health, store: "マツキヨ"),
                     item("2026-11-04", 40_000)]
        let pick: (OverspendAnalysis) -> [InsightTarget] = { result in
            result.drivers.map(\.target).filter { $0 == .category(.kids) || $0 == .category(.health) }
        }
        let first = pick(analysis(items, budget: 45_000))
        let again = pick(analysis(items.reversed(), budget: 45_000))
        #expect(first == again)
        let kids = ExpenseCategory.allCases.firstIndex(of: .kids)!, health = ExpenseCategory.allCases.firstIndex(of: .health)!
        let expected: [InsightTarget] = kids < health ? [.category(.kids), .category(.health)] : [.category(.health), .category(.kids)]
        #expect(Array(first.prefix(2)) == expected)
    }

    @Test func explainedShareOfTheOverspend() throws {
        let items = [item("2026-11-03", 38_000, .groceries, store: "西友"), item("2026-11-04", 22_000)]
        let result = analysis(items, budget: 50_000)        // over by ¥10,000
        #expect(result.insight.state == .overBudget)
        #expect(result.basisYen == 10_000)
        #expect(result.explainedYen >= 28_000)
        #expect(result.explainedShare == 1, "capped at the whole overspend")
    }

    @Test func onPaceExplainsSpendAboveTheUsualPace() throws {
        // Usual by mid-month: groceries 15,000 + dining 5,000 = 20,000. Spent 32,000 → 12,000 above.
        let items = [item("2026-11-03", 6_200, .kids, store: "西松屋"), item("2026-11-04", 25_800)]
        let result = analysis(items, budget: 40_000)
        #expect(result.insight.state == .onPaceToOverspend)
        #expect(result.basisYen == 12_000)
        let share = try #require(result.explainedShare)
        #expect(share > 0 && share <= 1)
    }

    @Test func noInsightNoDrivers() {
        let result = analysis([item("2026-11-03", 6_200, .kids, store: "西松屋")], budget: 100_000)
        #expect(result.insight.state == .none)
        #expect(result.drivers.isEmpty)
        #expect(result.basisYen == nil)
    }
}

// MARK: - Rest-of-month amounts

@Suite struct RestOfMonthTests {
    /// floor(max(B − S, 0) ÷ remaining days, today included): ¥10,000 left over 16 days.
    @Test func dailyAmountKeepsTheMonthOnBudget() {
        let result = analysis([item("2026-11-03", 40_000)], budget: 50_000)
        #expect(result.insight.state == .onPaceToOverspend)
        #expect(result.dailyAmountYen == 625)
        #expect(result.weeklyAmountYen == result.insight.summary.weeklyAllowance?.yen)
        #expect(result.weeklyAmountYen != nil)
    }

    @Test func overBudgetAmountsAreZero() {
        let result = analysis([item("2026-11-03", 60_000)], budget: 50_000)
        #expect(result.isOverBudget)
        #expect(result.dailyAmountYen == 0)
        #expect(result.weeklyAmountYen == 0)
    }

    /// Closed months: read-only analysis, no rest-of-month figures in any suggestion.
    @Test func closedMonthHasNoRestOfMonthSuggestions() throws {
        let october = LedgerMonth(year: 2026, month: 10)
        let history = steadyHistory().filter { !$0.dayKey.hasPrefix("2026-10") }
        let items = (1...9).map { item(String(format: "2026-10-%02d", $0 * 3), 2_000, .dining, store: "喫茶ポエム") }
            + [item("2026-10-02", 30_000), item("2026-10-05", 12_000, .dining, store: "喫茶ポエム")]
        let result = OverspendAnalysis(month: october, budget: .yen(40_000), items: items, history: history, now: midNovember)
        #expect(result.insight.state == .closedMonthOverBudget)
        #expect(result.dailyAmountYen == nil)
        #expect(result.weeklyAmountYen == nil)
        #expect(!result.drivers.isEmpty)
        for driver in result.drivers {
            switch driver.suggestion {
            case .categoryIncrease(_, _, let keepTo): #expect(keepTo == nil)
            case .moreVisits(_, _, _, let fewer, let saving): #expect(fewer == nil && saving == nil)
            default: break
            }
        }
    }

    @Test func lastDayHasNoVisitsLeftToSave() throws {
        let items = (1...7).map { item(String(format: "2026-11-%02d", $0 * 4), 1_000, .dining, store: "喫茶ポエム") }
            + [item("2026-11-01", 45_000)]
        let result = analysis(items, budget: 45_000, now: tokyo("2026-11-30"))
        // Usual 4 a month; 7 visits is not 1.5× + 3 extra by the end of the month, so check any visits driver.
        for driver in result.drivers {
            if case .moreVisits(_, _, _, let fewer, _) = driver.suggestion { #expect(fewer == nil) }
        }
        #expect(result.dailyAmountYen == 0)
    }
}

// MARK: - Limited history

@Suite struct LimitedHistoryDriverTests {
    @Test func topThreeCategoriesByShareOfBudget() throws {
        let items = [item("2026-11-02", 20_000), item("2026-11-03", 9_000, .dining), item("2026-11-04", 6_000, .kids),
                     item("2026-11-05", 4_000, .health), item("2026-11-06", 3_000, .groceries)]
        let result = analysis(items, budget: 40_000, history: [])
        #expect(result.isLimitedHistory)
        #expect(result.drivers.map(\.kind) == [.shareOfBudget, .shareOfBudget, .shareOfBudget])
        #expect(result.drivers.map(\.target) == [.category(.groceries), .category(.dining), .category(.kids)])
        #expect(result.drivers.first?.suggestion == .shareOfBudget(.groceries, spentYen: 23_000, percentOfBudget: 57))
        #expect(result.drivers.first?.itemIndices == [0, 4])
        // Over budget by ¥2,000.
        #expect(result.basisYen == 2_000)
    }

    @Test func noOneOffOrNewSpendingWithoutABaseline() {
        let items = [item("2026-11-02", 38_000, .shopping, store: "ニトリ"), item("2026-11-03", 5_000)]
        let result = analysis(items, budget: 40_000, history: [])
        #expect(result.drivers.allSatisfy { $0.kind == .shareOfBudget })
    }

    @Test func onPaceInLimitedHistoryExplainsTheSpend() {
        let result = analysis([item("2026-11-02", 35_000)], budget: 40_000, history: [])
        #expect(result.insight.state == .onPaceToOverspend)
        #expect(result.basisYen == 35_000)
        #expect(result.explainedShare == 1)
    }
}

@Suite struct MedianTests {
    @Test func evenCountRoundsDown() {
        let history = [item("2026-10-01", 1_000, .dining), item("2026-10-02", 2_001, .dining)]
        // Median of 1,000 and 2,001 rounds down to 1,500; 4,500 = 3×.
        let items = [item("2026-11-03", 4_500, .dining), item("2026-11-04", 90_000)]
        let result = OverspendAnalysis(month: november, budget: .yen(100_000), items: items, history: history, now: midNovember)
        let oneOff = result.drivers.first { $0.kind == .largeOneOff && $0.target == .category(.dining) }
        #expect(oneOff?.impactYen == 3_000)
    }
}

@Suite struct InsightTargetTests {
    @Test func categoryMatchesItsExpenses() {
        #expect(InsightTarget.category(.dining).matches(item("2026-11-02", 1_000, .dining)))
        #expect(!InsightTarget.category(.dining).matches(item("2026-11-02", 1_000, .groceries)))
    }

    /// Same grouping as the drivers: trimmed saved names; an unknown store matches nothing.
    @Test func storeMatchesTrimmedNames() {
        #expect(InsightTarget.store("西友").matches(item("2026-11-02", 1_000, store: " 西友 ")))
        #expect(!InsightTarget.store("西友").matches(item("2026-11-02", 1_000, store: "ローソン")))
        #expect(!InsightTarget.store("").matches(item("2026-11-02", 1_000, store: "")))
        #expect(!InsightTarget.store(" ").matches(item("2026-11-02", 1_000, store: "")))
    }
}
