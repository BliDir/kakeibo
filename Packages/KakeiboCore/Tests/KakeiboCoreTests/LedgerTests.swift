import Foundation
import Testing
import KakeiboCore

private struct Item: LedgerItem {
    var dayKey: String
    var totalYen: Int
    var tax10Yen: Int?
    var tax8Yen: Int?
    var category: ExpenseCategory
}

@Suite struct LedgerMonthTests {
    @Test func navigation() {
        let nov = LedgerMonth(year: 2026, month: 11)
        #expect(nov.key == "2026-11")
        #expect(nov.previous == LedgerMonth(year: 2026, month: 10))
        #expect(nov.next.next == LedgerMonth(year: 2027, month: 1))
        #expect(LedgerMonth(year: 2026, month: 1).previous == LedgerMonth(year: 2025, month: 12))
        #expect(nov.previous < nov)
    }

    @Test func fromDateAndDayKey() {
        // 2026-10-31 23:30 UTC is 2026-11-01 08:30 in Tokyo.
        #expect(LedgerMonth(containing: Date(timeIntervalSince1970: 1_793_489_400)) == LedgerMonth(year: 2026, month: 11))
        #expect(LedgerMonth(dayKey: "2026-10-31") == LedgerMonth(year: 2026, month: 10))
        #expect(LedgerMonth(dayKey: "bad") == nil)
        #expect(DayKey.make(from: LedgerMonth(year: 2026, month: 11).firstDay) == "2026-11-01")
    }

    @Test(arguments: [
        (2026, 11, "令和8年11月", "Reiwa 8"),
        (2019, 5, "令和元年5月", "Reiwa 1"),
        (2019, 4, "平成31年4月", "Heisei 31"),
        (2020, 1, "令和2年1月", "Reiwa 2"),
    ])
    func japaneseEra(year: Int, month: Int, label: String, english: String) {
        let m = LedgerMonth(year: year, month: month)
        #expect(JapaneseEra.label(for: m) == label)
        #expect(JapaneseEra.englishYear(for: m) == english)
    }
}

@Suite struct MonthSummaryTests {
    @Test func totalsCountTaxAndCategories() {
        let items = [
            Item(dayKey: "2026-11-01", totalYen: 1_310, tax10Yen: 29, tax8Yen: 72, category: .groceries),
            Item(dayKey: "2026-11-01", totalYen: 1_078, tax10Yen: 98, category: .dining),
            Item(dayKey: "2026-11-02", totalYen: 690, tax8Yen: 51, category: .groceries),
            Item(dayKey: "2026-11-03", totalYen: 2_150, category: .transport),
        ]
        let s = MonthSummary(items)
        #expect(s.totalYen == 5_228)
        #expect(s.count == 4)
        #expect(s.taxYen == 250)
        #expect(s.tax8Yen == 123)
        #expect(s.tax10Yen == 127)
        #expect(s.categories.map(\.category) == [.transport, .groceries, .dining])
        #expect(s.categories.map(\.totalYen) == [2_150, 2_000, 1_078])
        #expect(s.categories.map(\.count) == [1, 2, 1])
        #expect(abs(s.categories.map(\.share).reduce(0, +) - 1) < 1e-9)
    }

    @Test func barsAreRelativeToTheLargestCategory() {
        let s = MonthSummary([
            Item(dayKey: "2026-11-01", totalYen: 800, category: .groceries),
            Item(dayKey: "2026-11-01", totalYen: 200, category: .dining),
        ])
        #expect(s.categories.map(\.barFraction) == [1.0, 0.25])
        #expect(s.categories.map(\.share) == [0.8, 0.2])
    }

    @Test func everyCategoryIsLabelled() {
        // The legend shows both names, so every category needs both.
        for category in ExpenseCategory.allCases {
            #expect(!category.japaneseName.isEmpty)
            #expect(!category.englishName.isEmpty)
        }
    }

    @Test func emptyMonth() {
        let s = MonthSummary([Item]())
        #expect(s == .empty)
    }

    @Test func tiesKeepCategoryOrder() {
        let s = MonthSummary([Item(dayKey: "2026-11-01", totalYen: 500, category: .other),
                              Item(dayKey: "2026-11-01", totalYen: 500, category: .groceries)])
        #expect(s.categories.map(\.category) == [.groceries, .other])
    }
}

@Suite struct MonthComparisonTests {
    private func summary(_ total: Int) -> MonthSummary {
        total == 0 ? .empty : MonthSummary([Item(dayKey: "2026-11-01", totalYen: total, category: .other)])
    }

    @Test func higherThanLastMonth() {
        let c = MonthComparison(current: summary(186_420), previous: summary(178_180))
        #expect(c.differenceYen == 8_240)
        #expect(c.direction == .up)
        #expect(abs(c.change! - 0.04624) < 0.0001)
    }

    @Test func lowerThanLastMonth() {
        let c = MonthComparison(current: summary(900), previous: summary(1_200))
        #expect(c.differenceYen == -300)
        #expect(c.direction == .down)
        #expect(c.change == -0.25)
    }

    @Test func sameAsLastMonth() {
        let c = MonthComparison(current: summary(500), previous: summary(500))
        #expect(c.direction == .same)
        #expect(c.change == 0)
    }

    @Test func noChangeWhenLastMonthWasEmpty() {
        let c = MonthComparison(current: summary(500), previous: summary(0))
        #expect(c.differenceYen == 500)
        #expect(c.change == nil)
    }
}

@Suite struct DayGroupTests {
    @Test func groupsNewestDayFirstWithSubtotals() {
        let items = [
            Item(dayKey: "2026-11-03", totalYen: 100, category: .other),
            Item(dayKey: "2026-11-01", totalYen: 300, category: .other),
            Item(dayKey: "2026-11-03", totalYen: 200, category: .other),
            Item(dayKey: "2026-11-02", totalYen: 400, category: .other),
        ]
        let groups = DayGroup.group(items)
        #expect(groups.map(\.dayKey) == ["2026-11-03", "2026-11-02", "2026-11-01"])
        #expect(groups.map(\.subtotalYen) == [300, 400, 300])
        #expect(groups[0].items.map(\.totalYen) == [100, 200])   // order kept
        #expect(DayGroup<Item>.group([]).isEmpty)
    }
}
