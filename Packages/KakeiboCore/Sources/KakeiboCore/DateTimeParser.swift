import Foundation

/// Reads the purchase date and time from normalized receipt lines.
///
/// Dates:
/// - Western: `2026/11/03`, `2026-11-03`, `2026.11.03`, `2026年11月3日`
/// - Era: `令和8年11月3日`, `令和元年…`, `R8.11.3`, `R08/11/03` (令和N = 2018 + N), and 平成/H for old receipts
/// - Short year: `26/11/03` (2026); a 1-digit year such as `8.10.28` is a 令和 year
/// - Month and day only: `11月3日`, year taken from `today`
///
/// The first valid date wins, except that dates on expiry lines (有効期限, まで)
/// and dates in the future lose to any other date.
///
/// Times: `18:42`, `18:42:10`, `18時42分`. Date text is removed before looking for a time,
/// and the time on the date's line wins over times elsewhere. Opening-hours lines are skipped.
public enum DateTimeParser {
    public struct DateResult: Sendable, Equatable {
        /// `yyyy-MM-dd`.
        public var dayKey: String
        /// `high` for a full date, `medium` for month-day only, `low` for a date in the future.
        public var confidence: Confidence
        /// Index of the line the date came from.
        public var lineIndex: Int
    }

    public struct Result: Sendable, Equatable {
        public var date: DateResult?
        /// `HH:mm`.
        public var time: String?
    }

    /// Parses date and time together. `today` is the scan date, used for month-day dates and future checks.
    public static func parse(lines: [String], today: Date) -> Result {
        let date = parseDate(lines: lines, today: today)
        return Result(date: date, time: parseTime(lines: lines, preferringLine: date?.lineIndex))
    }

    // MARK: - Date

    public static func parseDate(lines: [String], today: Date) -> DateResult? {
        let todayParts = tokyoCalendar.dateComponents([.year, .month, .day], from: today)
        let todayYMD = YMD(year: todayParts.year!, month: todayParts.month!, day: todayParts.day!)

        var candidates: [(ymd: YMD, confidence: Confidence, line: Int, rank: Int)] = []
        for (index, line) in lines.enumerated() {
            let isExpiry = expiryWords.contains { line.contains($0) }
            for found in dates(in: line, today: todayYMD) {
                let isFuture = found.ymd > todayYMD.addingOneDay
                let confidence: Confidence = isFuture ? .low : found.confidence
                // Lower rank wins: plain dates, then expiry-line dates, then future dates.
                let rank = (isFuture ? 2 : 0) + (isExpiry ? 1 : 0)
                candidates.append((found.ymd, confidence, index, rank))
            }
        }
        // Prefer full dates over month-day, then the rank, then the first on the receipt.
        guard let best = candidates.enumerated().min(by: { a, b in
            let ka = (a.element.rank, a.element.confidence == .medium ? 1 : 0, a.offset)
            let kb = (b.element.rank, b.element.confidence == .medium ? 1 : 0, b.offset)
            return ka < kb
        })?.element else { return nil }
        return DateResult(dayKey: best.ymd.dayKey, confidence: best.confidence, lineIndex: best.line)
    }

    /// Every valid date on a line, left to right.
    static func dates(in line: String, today: YMD) -> [(ymd: YMD, confidence: Confidence, range: NSRange)] {
        var found: [(YMD, Confidence, NSRange)] = []
        var taken: [NSRange] = []

        func overlapsTaken(_ r: NSRange) -> Bool { taken.contains { NSIntersectionRange($0, r).length > 0 } }

        for (pattern, kind) in datePatterns {
            for match in pattern.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard !overlapsTaken(match.range) else { continue }
                let g = { (i: Int) -> String? in
                    Range(match.range(at: i), in: line).map { String(line[$0]) }
                }
                guard let ymd = kind.resolve(g, today: today), ymd.isValid else { continue }
                found.append((ymd, kind == .monthDay ? .medium : .high, match.range))
                taken.append(match.range)
            }
        }
        return found.sorted { $0.2.location < $1.2.location }
    }

    private enum DateKind: Equatable {
        case western, era, shortYear, monthDay

        func resolve(_ g: (Int) -> String?, today: YMD) -> YMD? {
            switch self {
            case .western:
                guard let y = g(1).flatMap(Int.init), let m = g(2).flatMap(Int.init), let d = g(3).flatMap(Int.init) else { return nil }
                return YMD(year: y, month: m, day: d)
            case .era:
                guard let era = g(1), let yText = g(2), let m = g(3).flatMap(Int.init), let d = g(4).flatMap(Int.init) else { return nil }
                guard let n = yText == "元" ? 1 : Int(yText), n >= 1 else { return nil }
                let base = (era == "令和" || era.uppercased() == "R") ? 2018 : 1988
                return YMD(year: base + n, month: m, day: d)
            case .shortYear:
                guard let yText = g(1), let y = Int(yText), let m = g(2).flatMap(Int.init), let d = g(3).flatMap(Int.init) else { return nil }
                if yText.count == 1 {
                    return YMD(year: 2018 + y, month: m, day: d)
                }
                // 2 digits: 20yy or 令和yy. Take the one closest to today that is not in the future.
                let options = [YMD(year: 2000 + y, month: m, day: d), YMD(year: 2018 + y, month: m, day: d)]
                let notFuture = options.filter { $0 <= today.addingOneDay }
                return notFuture.max() ?? options.min()
            case .monthDay:
                guard let m = g(1).flatMap(Int.init), let d = g(2).flatMap(Int.init) else { return nil }
                let thisYear = YMD(year: today.year, month: m, day: d)
                // A December receipt scanned in January belongs to last year.
                return thisYear > today.addingOneDay ? YMD(year: today.year - 1, month: m, day: d) : thisYear
            }
        }
    }

    /// Tried in order; a later pattern cannot reuse text an earlier one matched.
    private static let datePatterns: [(NSRegularExpression, DateKind)] = ([
        (#"(令和|平成|(?<![A-Za-z])[RH])\s*(元|\d{1,2})\s*[/\-.年]\s*(\d{1,2})\s*[/\-.月]\s*(\d{1,2})\s*日?"#, .era),
        (#"(?<!\d)((?:19|20)\d{2})\s*[/\-.年]\s*(\d{1,2})\s*[/\-.月]\s*(\d{1,2})(?!\d)\s*日?"#, .western),
        (#"(?<![\d.:/\-])(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{1,2})(?![\d.:/\-])"#, .shortYear),
        (#"(?<![\d年])(\d{1,2})\s*月\s*(\d{1,2})\s*日"#, .monthDay),
    ] as [(String, DateKind)]).map { (try! NSRegularExpression(pattern: $0.0, options: .caseInsensitive), $0.1) }

    private static let expiryWords = ["有効期限", "期限", "まで", "有効期間"]

    // MARK: - Time

    /// The first valid time, taken from `preferringLine` when that line has one.
    public static func parseTime(lines: [String], preferringLine: Int? = nil) -> String? {
        if let index = preferringLine, lines.indices.contains(index), let time = time(in: lines[index]) {
            return time
        }
        for line in lines where !openingHoursWords.contains(where: line.contains) {
            if let time = time(in: line) { return time }
        }
        return nil
    }

    /// A time on one line, ignoring any digits that belong to a date.
    static func time(in line: String) -> String? {
        var masked = line
        // Blank out date text so its digits cannot be read as a time.
        let anyDay = YMD(year: 2000, month: 1, day: 1)
        for found in dates(in: line, today: anyDay).reversed() {
            if let r = Range(found.range, in: masked) {
                masked.replaceSubrange(r, with: String(repeating: " ", count: masked[r].count))
            }
        }
        let range = NSRange(masked.startIndex..., in: masked)
        for match in timePattern.matches(in: masked, range: range) {
            guard let hText = Range(match.range(at: 1), in: masked).map({ masked[$0] }),
                  let mText = (Range(match.range(at: 2), in: masked) ?? Range(match.range(at: 3), in: masked)).map({ masked[$0] }),
                  let h = Int(hText), let m = Int(mText), (0...23).contains(h), (0...59).contains(m)
            else { continue }
            return String(format: "%02d:%02d", h, m)
        }
        return nil
    }

    /// `18:42` or `18:42:10` (minutes always 2 digits), or `18時42分` / `8時5分`.
    private static let timePattern = try! NSRegularExpression(
        pattern: #"(?<![\d:])(\d{1,2})\s*(?::(\d{2})(?::\d{2})?(?![\d:])|時\s*(\d{1,2})\s*分)"#
    )

    private static let openingHoursWords = ["営業時間", "受付時間", "営業", "OPEN", "open"]

    // MARK: - Calendar

    private static let tokyoCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = KakeiboCore.timeZone
        return calendar
    }()
}

/// A calendar date without a time zone, compared as (year, month, day).
struct YMD: Comparable, Sendable, Hashable {
    var year: Int
    var month: Int
    var day: Int

    var dayKey: String { String(format: "%04d-%02d-%02d", year, month, day) }

    var isValid: Bool {
        (1989...2099).contains(year) && (1...12).contains(month) && (1...daysInMonth).contains(day)
    }

    private var daysInMonth: Int {
        switch month {
        case 2: isLeapYear ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    private var isLeapYear: Bool { (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 }

    /// The next calendar day. Allows for the phone's date being a little behind the receipt.
    var addingOneDay: YMD {
        if day < daysInMonth { return YMD(year: year, month: month, day: day + 1) }
        if month < 12 { return YMD(year: year, month: month + 1, day: 1) }
        return YMD(year: year + 1, month: 1, day: 1)
    }

    static func < (a: YMD, b: YMD) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}
