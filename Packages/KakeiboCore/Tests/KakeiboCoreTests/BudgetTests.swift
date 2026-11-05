import Foundation
import Testing
@testable import KakeiboCore

private struct Item: LedgerItem {
    var dayKey: String
    var totalYen: Int
    var tax10Yen: Int? = nil
    var tax8Yen: Int? = nil
    var category: ExpenseCategory = .other
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

private func summary(_ budget: MonthlyBudget, spent: Int, on dayKey: String, month key: String? = nil) -> BudgetSummary {
    BudgetSummary(month: month(key ?? String(dayKey.prefix(7))), budget: budget, spentYen: spent, now: tokyo(dayKey))
}

// MARK: - Weekly allowance

@Suite struct WeeklyAllowanceTests {
    @Test func releasePlanExample() throws {
        // ¥100,000 budget, ¥40,000 spent, Wednesday 12 August 2026: D = 20, W = 5 → ¥15,000.
        let s = summary(.yen(100_000), spent: 40_000, on: "2026-08-12")
        let w = try #require(s.weeklyAllowance)
        #expect(w.daysLeftInMonth == 20)
        #expect(w.daysLeftInWeek == 5)
        #expect(w.yen == 15_000)
        #expect(w.fromDayKey == "2026-08-12")
        #expect(w.throughDayKey == "2026-08-16")   // Sunday
        #expect(s.remainingYen == 60_000)
    }

    @Test(arguments: [
        // dayKey, D, W, through
        ("2026-11-02", 29, 7, "2026-11-08"),   // Monday: a full week
        ("2026-11-05", 26, 4, "2026-11-08"),   // Thursday
        ("2026-11-01", 30, 1, "2026-11-01"),   // Sunday the 1st: the week is just today
        ("2026-10-29", 3, 3, "2026-10-31"),    // Thursday, week clipped to Saturday 31st
        ("2026-11-30", 1, 1, "2026-11-30"),    // last day, a Monday: clipped to the month
        ("2026-09-30", 1, 1, "2026-09-30"),    // last day of a 30-day month
        ("2026-12-28", 4, 4, "2026-12-31"),    // Monday, week clipped at the year end
        ("2026-12-31", 1, 1, "2026-12-31"),    // last day of the year
        ("2027-02-28", 1, 1, "2027-02-28"),    // 28-day February
        ("2028-02-28", 2, 2, "2028-02-29"),    // leap year: the 29th exists
        ("2028-02-29", 1, 1, "2028-02-29"),    // leap day
    ])
    func daysLeft(dayKey: String, d: Int, w: Int, through: String) throws {
        let allowance = try #require(summary(.yen(100_000), spent: 0, on: dayKey).weeklyAllowance)
        #expect(allowance.daysLeftInMonth == d)
        #expect(allowance.daysLeftInWeek == w)
        #expect(allowance.throughDayKey == through)
    }

    @Test func lastDayGetsEverythingLeft() throws {
        let w = try #require(summary(.yen(100_000), spent: 12_345, on: "2026-11-30").weeklyAllowance)
        #expect(w.yen == 87_655)
    }

    @Test func roundsDown() throws {
        // ¥100 left over 3 days, 1 of them this week: 33.3 → ¥33.
        let w = try #require(summary(.yen(1_000), spent: 900, on: "2026-10-29", month: "2026-10").weeklyAllowance)
        #expect(w.daysLeftInMonth == 3 && w.daysLeftInWeek == 3)
        #expect(w.yen == 100)
        let sunday = try #require(summary(.yen(1_000), spent: 900, on: "2026-11-01").weeklyAllowance)
        #expect(sunday.daysLeftInMonth == 30 && sunday.daysLeftInWeek == 1)
        #expect(sunday.yen == 3)   // 100 / 30 = 3.33
    }

    @Test func overspentOrExactlySpentGivesZero() throws {
        #expect(summary(.yen(50_000), spent: 50_000, on: "2026-11-05").weeklyAllowance?.yen == 0)
        #expect(summary(.yen(50_000), spent: 80_000, on: "2026-11-05").weeklyAllowance?.yen == 0)
    }

    @Test func onlyTheCurrentMonthHasOne() {
        // Viewing October on 5 November, and December on 5 November.
        #expect(summary(.yen(100_000), spent: 10_000, on: "2026-11-05", month: "2026-10").weeklyAllowance == nil)
        #expect(summary(.yen(100_000), spent: 10_000, on: "2026-11-05", month: "2026-12").weeklyAllowance == nil)
        // A past month still has its budget comparison.
        #expect(summary(.yen(100_000), spent: 10_000, on: "2026-11-05", month: "2026-10").remainingYen == 90_000)
    }

    @Test func usesTokyoTimeNotTheDevicesTimeZone() throws {
        // 2026-11-01 15:30 UTC is Monday 2 November 00:30 in Tokyo, but still Sunday in UTC.
        let instant = Date(timeIntervalSince1970: 1_793_547_000)
        let s = BudgetSummary(month: LedgerMonth(year: 2026, month: 11), budget: .yen(100_000), spentYen: 0, now: instant)
        let w = try #require(s.weeklyAllowance)
        #expect(w.fromDayKey == "2026-11-02")
        #expect(w.daysLeftInWeek == 7)
        #expect(w.daysLeftInMonth == 29)

        // 23:59 on the last day in Tokyo is still the last day; one minute later is the next month.
        let lastMinute = tokyo("2026-10-31", 23, 59)
        #expect(BudgetSummary(month: month("2026-10"), budget: .yen(1_000), spentYen: 0, now: lastMinute)
            .weeklyAllowance?.daysLeftInMonth == 1)
        let nextMonth = tokyo("2026-11-01", 0, 0)
        #expect(BudgetSummary(month: month("2026-10"), budget: .yen(1_000), spentYen: 0, now: nextMonth)
            .weeklyAllowance == nil)
    }

    @Test func injectedCalendarDecidesTheDay() throws {
        // A UTC calendar puts the same instant on Sunday 1 November: proves the calendar is used.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let instant = Date(timeIntervalSince1970: 1_793_547_000)
        let w = try #require(WeeklyAllowance(month: month("2026-11"), remainingYen: 30_000, now: instant, calendar: utc))
        #expect(w.fromDayKey == "2026-11-01")
        #expect(w.daysLeftInWeek == 1)
        #expect(w.yen == 1_000)
    }

    @Test func largeAmountsDoNotOverflow() {
        // floor(R × W / D) for R near Int.max: R × W alone would overflow.
        let r = Int.max - 6
        let share = WeeklyAllowance.share(of: r, days: 6, of: 7)
        #expect(share == r / 7 * 6 + (r % 7) * 6 / 7)
        #expect(WeeklyAllowance.share(of: Int.max, days: 31, of: 31) == Int.max)
        #expect(WeeklyAllowance.share(of: 0, days: 3, of: 20) == 0)
    }
}

// MARK: - Summary

@Suite struct BudgetSummaryTests {
    @Test func activeBudget() {
        let s = summary(.yen(100_000), spent: 40_000, on: "2026-08-12")
        #expect(s.status == .active)
        #expect(s.budgetYen == 100_000)
        #expect(s.spentYen == 40_000)
        #expect(s.remainingYen == 60_000)
        #expect(s.overspentYen == 0)
        #expect(!s.isOverBudget)
        #expect(s.percentSpent == 40)
        #expect(s.progressFraction == 0.4)
    }

    @Test func overspendIsKeptSignedAndNotClamped() {
        let s = summary(.yen(100_000), spent: 130_500, on: "2026-11-05")
        #expect(s.remainingYen == -30_500)
        #expect(s.overspentYen == 30_500)
        #expect(s.isOverBudget)
        #expect(s.percentSpent == 130)       // the shown percentage is not clamped
        #expect(s.progressFraction == 1)     // only the bar is
        #expect(s.weeklyAllowance?.yen == 0)
    }

    @Test func percentRoundsDown() {
        #expect(summary(.yen(3), spent: 2, on: "2026-11-05").percentSpent == 66)
        #expect(summary(.yen(100_000), spent: 79_999, on: "2026-11-05").percentSpent == 79)
        #expect(summary(.yen(100_000), spent: 80_000, on: "2026-11-05").percentSpent == 80)
    }

    @Test func unsetBudgetHasNoFigures() {
        let s = summary(.unset, spent: 40_000, on: "2026-11-05")
        #expect(s.status == .unset)
        #expect(s.spentYen == 40_000)          // spend is still known
        #expect(s.remainingYen == nil)
        #expect(s.percentSpent == nil)
        #expect(s.progressFraction == nil)
        #expect(s.weeklyAllowance == nil)
    }

    @Test func invalidBudgetHasNoFigures() {
        for problem in [MonthlyBudget.Problem.notPositive, .tooLarge, .notWholeYen] {
            let s = summary(.invalid(problem), spent: 1_000, on: "2026-11-05")
            #expect(s.status == .invalid(problem))
            #expect(s.remainingYen == nil && s.weeklyAllowance == nil)
        }
        // A `.yen` built directly with a bad value is caught too: no division by zero.
        #expect(summary(.yen(0), spent: 1_000, on: "2026-11-05").status == .invalid(.notPositive))
        #expect(summary(.yen(-5), spent: 1_000, on: "2026-11-05").status == .invalid(.notPositive))
        #expect(summary(.yen(MonthlyBudget.maximumYen + 1), spent: 0, on: "2026-11-05").status == .invalid(.tooLarge))
    }

    @Test func spendUsesTheLedgerTotal() {
        // Scans, manual entries and a refund (negative total) all count, as in MonthSummary.
        let items = [
            Item(dayKey: "2026-11-02", totalYen: 1_310),
            Item(dayKey: "2026-11-03", totalYen: 2_150),
            Item(dayKey: "2026-11-04", totalYen: -500),
        ]
        let s = BudgetSummary(month: month("2026-11"), budget: .yen(10_000), items: items, now: tokyo("2026-11-05"))
        #expect(s.spentYen == MonthSummary(items).totalYen)
        #expect(s.spentYen == 2_960)
        #expect(s.remainingYen == 7_040)
    }

    @Test func refundsBeyondSpendGiveNegativeSpend() {
        let s = summary(.yen(10_000), spent: -2_000, on: "2026-11-05")
        #expect(s.remainingYen == 12_000)
        #expect(s.percentSpent == -20)
        #expect(s.progressFraction == 0)
        #expect(summary(.yen(3), spent: -1, on: "2026-11-05").percentSpent == -34)   // floor(−33.3)
    }

    @Test func noExpensesIsZeroSpend() {
        let s = BudgetSummary(month: month("2026-11"), budget: .yen(50_000), items: [Item](), now: tokyo("2026-11-05"))
        #expect(s.spentYen == 0)
        #expect(s.remainingYen == 50_000)
        #expect(s.percentSpent == 0)
    }

    @Test func largestBudget() {
        let s = summary(.yen(MonthlyBudget.maximumYen), spent: 1, on: "2026-11-02")
        #expect(s.remainingYen == 999_999_998)
        #expect(s.weeklyAllowance?.yen == 999_999_998 / 29 * 7 + (999_999_998 % 29) * 7 / 29)
    }

    @Test func overflowIsAStateNotACrash() {
        // Spend that cannot be added up.
        let items = [Item(dayKey: "2026-11-01", totalYen: Int.max), Item(dayKey: "2026-11-02", totalYen: 1)]
        #expect(MonthSpend.total(items) == nil)
        let s = BudgetSummary(month: month("2026-11"), budget: .yen(1_000), items: items, now: tokyo("2026-11-05"))
        #expect(s.status == .outOfRange)
        #expect(s.remainingYen == nil && s.weeklyAllowance == nil && s.percentSpent == nil)

        // B − S that does not fit.
        let t = summary(.yen(1_000), spent: Int.min, on: "2026-11-05")
        #expect(t.status == .outOfRange)

        // Huge spend still gives a percentage.
        #expect(summary(.yen(1), spent: Int.max, on: "2026-11-05").percentSpent == Int.max)
    }
}

// MARK: - Budget input

@Suite struct MonthlyBudgetTests {
    @Test(arguments: [
        ("100000", 100_000),
        ("100,000", 100_000),
        ("¥100,000", 100_000),
        ("100,000円", 100_000),
        ("１００，０００", 100_000),       // full-width digits and comma
        ("￥５０００", 5_000),             // full-width yen sign
        (" 2500 ", 2_500),
        ("0001200", 1_200),               // leading zeros
        ("999999999", 999_999_999),        // the maximum
    ])
    func validInput(text: String, yen: Int) {
        #expect(MonthlyBudget.parse(text) == .yen(yen))
    }

    @Test(arguments: ["", "   ", "\n"])
    func emptyIsUnset(text: String) {
        #expect(MonthlyBudget.parse(text) == .unset)
    }

    @Test(arguments: [
        ("0", MonthlyBudget.Problem.notPositive),
        ("０", .notPositive),
        ("-500", .notPositive),
        ("−500", .notPositive),
        ("1000000000", .tooLarge),
        ("99999999999999999999999", .tooLarge),   // would overflow Int
        ("1000.5", .notWholeYen),
        ("10.00", .notWholeYen),
        ("1e5", .notWholeYen),
        ("abc", .notWholeYen),
        ("+500", .notWholeYen),
        (",", .notWholeYen),
        ("¥", .notWholeYen),
    ])
    func invalidInput(text: String, problem: MonthlyBudget.Problem) {
        #expect(MonthlyBudget.parse(text) == .invalid(problem))
    }

    @Test func storedValues() {
        #expect(MonthlyBudget.validated(nil) == .unset)
        #expect(MonthlyBudget.validated(50_000) == .yen(50_000))
        #expect(MonthlyBudget.validated(0) == .invalid(.notPositive))
        #expect(MonthlyBudget.validated(Int.max) == .invalid(.tooLarge))
        #expect(MonthlyBudget.yen(5).yen == 5)
        #expect(MonthlyBudget.unset.yen == nil)
    }
}

@Suite struct NextDayTests {
    @Test func nextTokyoMidnight() {
        let next = Calendar.kakeibo.startOfNextDay(after: tokyo("2026-11-05", 23, 59))
        #expect(next == tokyo("2026-11-06", 0, 0))
        #expect(Calendar.kakeibo.startOfNextDay(after: tokyo("2026-11-30", 12)) == tokyo("2026-12-01", 0, 0))
        #expect(Calendar.kakeibo.startOfNextDay(after: tokyo("2026-12-31", 0, 0)) == tokyo("2027-01-01", 0, 0))
        // An instant late on 1 Nov UTC is already 2 Nov in Tokyo: next midnight is 3 Nov Tokyo.
        #expect(Calendar.kakeibo.startOfNextDay(after: Date(timeIntervalSince1970: 1_793_547_000)) == tokyo("2026-11-03", 0, 0))
    }
}

