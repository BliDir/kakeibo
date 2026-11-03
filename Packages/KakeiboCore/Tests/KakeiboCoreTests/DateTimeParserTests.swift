import Foundation
import Testing
@testable import KakeiboCore

@Suite struct DateTimeParserTests {
    /// 2026-11-03 12:00 in Tokyo.
    static let today = Date(timeIntervalSince1970: 1_793_674_800)

    private func date(_ text: String, today: Date = Self.today) -> DateTimeParser.DateResult? {
        DateTimeParser.parseDate(lines: TextNormalizer.normalize(text: text), today: today)
    }

    private func time(_ text: String) -> String? {
        DateTimeParser.parse(lines: TextNormalizer.normalize(text: text), today: Self.today).time
    }

    @Test func todayFixtureIsNovemberThirdInTokyo() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = KakeiboCore.timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: Self.today)
        #expect((parts.year, parts.month, parts.day) == (2026, 11, 3))
    }

    // MARK: Western

    @Test(arguments: ["2026/11/03", "2026-11-03", "2026.11.03", "2026年11月3日", "2026年11月03日(火)",
                      "2026/11/3", "2026 年 11 月 3 日", "２０２６／１１／０３"])
    func parsesWesternDates(text: String) throws {
        let r = try #require(date(text))
        #expect(r.dayKey == "2026-11-03")
        #expect(r.confidence == .high)
    }

    // MARK: Era

    @Test(arguments: [
        ("令和8年11月3日", "2026-11-03"),
        ("R8.11.3", "2026-11-03"),
        ("R08/11/03", "2026-11-03"),
        ("r8.11.3", "2026-11-03"),
        ("令和元年5月1日", "2019-05-01"),
        ("令和7年12月31日", "2025-12-31"),
        ("平成31年4月30日", "2019-04-30"),
        ("H30.1.15", "2018-01-15"),
    ])
    func parsesEraDates(text: String, expected: String) throws {
        let r = try #require(date(text))
        #expect(r.dayKey == expected)
        #expect(r.confidence == .high)
    }

    // MARK: Short years and month-day

    @Test(arguments: [
        ("26/11/03", "2026-11-03"),
        ("25/12/31", "2025-12-31"),
        ("08/11/03", "2026-11-03"),   // 2008 is far older than 令和8 (2026)
        ("8.10.28", "2026-10-28"),    // 1-digit year is a 令和 year
    ])
    func parsesShortYears(text: String, expected: String) throws {
        #expect(try #require(date(text)).dayKey == expected)
    }

    @Test func monthDayUsesTodaysYear() throws {
        let r = try #require(date("11月3日(火)"))
        #expect(r.dayKey == "2026-11-03")
        #expect(r.confidence == .medium)
    }

    @Test func monthDayAfterTodayIsLastYear() throws {
        // Scanned on 2026-01-03, a 12月28日 receipt is from 2025.
        let jan3 = Date(timeIntervalSince1970: 1_767_409_200)
        #expect(try #require(date("12月28日", today: jan3)).dayKey == "2025-12-28")
    }

    // MARK: Validation

    @Test(arguments: ["2026/13/01", "2026/11/32", "2026/02/30", "2025/02/29", "令和8年0月1日", "11月31日"])
    func rejectsInvalidDates(text: String) {
        #expect(date(text) == nil)
    }

    @Test func acceptsLeapDay() {
        // Scanned on 2028-03-02 (Tokyo).
        let r = date("2028/02/29", today: Date(timeIntervalSince1970: 1_835_604_800))
        #expect(r?.dayKey == "2028-02-29")
        #expect(r?.confidence == .high)
    }

    // MARK: Choosing between dates

    @Test func purchaseDateBeatsExpiryDate() throws {
        let r = try #require(date("""
        ポイント有効期限 2027/03/31
        2026/11/03(火) 18:42
        """))
        #expect(r.dayKey == "2026-11-03")
        #expect(r.lineIndex == 1)
    }

    @Test func futureDateLosesAndIsLowWhenAlone() throws {
        #expect(try #require(date("2029/01/01\n2026/11/02")).dayKey == "2026-11-02")
        let alone = try #require(date("2029/01/01"))
        #expect(alone.confidence == .low)
    }

    @Test func fullDateBeatsMonthDay() throws {
        #expect(try #require(date("11月1日 セール\n2026/11/03")).dayKey == "2026-11-03")
    }

    @Test(arguments: ["東京都中野区本町1-1-1", "道玄坂2-10-7", "中野5-1-1", "26-11-03", "8/10.28"])
    func addressesAndMixedSeparatorsAreNotDates(text: String) {
        #expect(date(text) == nil)
    }

    @Test func fullDateBeatsShortYearAbove() throws {
        #expect(try #require(date("8.10.28\n2026/11/03")).dayKey == "2026-11-03")
    }

    @Test func noDate() {
        #expect(date("合計 ¥1,000\nTEL 03-1234-5678") == nil)
    }

    // MARK: Time

    @Test(arguments: [
        ("18:42", "18:42"),
        ("8:05", "08:05"),
        ("18:42:10", "18:42"),
        ("18時42分", "18:42"),
        ("2026/11/03(火) 18:42", "18:42"),
        ("令和8年11月3日 8時5分", "08:05"),
        ("令和8年11月3日 8時05分", "08:05"),
        ("18:4", nil),                     // colon form needs 2-digit minutes
    ] as [(String, String?)])
    func parsesTimes(text: String, expected: String?) {
        #expect(time(text) == expected)
    }

    @Test func doesNotReadDateDigitsAsTime() {
        #expect(time("8.10.28 12:05") == "12:05")
        #expect(time("8.10.28") == nil)
        #expect(time("2026.11.03") == nil)
    }

    @Test(arguments: ["25:00", "18:60", "TEL 03-1234-5678"])
    func rejectsInvalidTimes(text: String) {
        #expect(time(text) == nil)
    }

    @Test func prefersTimeOnDateLineAndSkipsOpeningHours() {
        let text = """
        営業時間 9:00-21:00
        レジ 2 担当 07:30
        2026/11/03 18:42
        """
        #expect(time(text) == "18:42")
        #expect(time("営業時間 9:00-21:00\nレジ 07:30") == "07:30")
    }
}
