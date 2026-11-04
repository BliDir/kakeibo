import Foundation

// Monthly budget and "Available this week" (v1.1, B-01).
//
// Rules (Kakeibo iOS v1.1 release plan, proposed defaults):
// - One overall budget per Tokyo month (Gregorian, `yyyy-MM`), whole positive yen.
// - Spend S is the month's ledger total: the same sum `MonthSummary.totalYen` uses, refunds included.
// - Remaining R = B − S keeps its sign; R < 0 is the overspent amount.
// - Weekly guidance only for the current Tokyo month:
//   floor(max(R, 0) × W / D), D = days from today to month end, W = days from today to
//   min(Sunday, month end), both inclusive of today. Weeks run Monday–Sunday.
// All arithmetic is whole-yen Int and overflow-checked; nothing here traps.

extension Calendar {
    /// Gregorian, Asia/Tokyo, weeks starting Monday: the calendar every budget rule uses.
    /// The device's own calendar and time zone never matter.
    public static let kakeibo: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = KakeiboCore.timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        return calendar
    }()
}

// MARK: - The budget amount

/// A month's budget as the user set it, or that it is missing or unusable.
public enum MonthlyBudget: Sendable, Equatable {
    /// No budget for the month: the screen shows a setup prompt, never a division by zero.
    case unset
    /// The stored or typed value cannot be a budget.
    case invalid(Problem)
    /// A valid budget, whole yen, 1 ... `maximumYen`.
    case yen(Int)

    public enum Problem: Sendable, Equatable {
        /// Zero or negative.
        case notPositive
        /// Has a fraction, letters, or other characters that are not a plain amount.
        case notWholeYen
        /// Above `maximumYen`.
        case tooLarge
    }

    /// ¥999,999,999: nine digits, the same limit as the expense amount field.
    public static let maximumYen = 999_999_999

    /// Checks a stored amount.
    public static func validated(_ yen: Int?) -> MonthlyBudget {
        guard let yen else { return .unset }
        if yen <= 0 { return .invalid(.notPositive) }
        if yen > maximumYen { return .invalid(.tooLarge) }
        return .yen(yen)
    }

    /// Reads what the user typed. Empty means unset. Accepts full-width digits (`１２３`),
    /// thousands separators and a ¥ or 円 sign (`¥1,000`, `1,000円`, `１，０００`); rejects
    /// signs, fractions and anything else rather than guessing.
    public static func parse(_ text: String) -> MonthlyBudget {
        // NFKC turns full-width digits, commas and ¥ into their ASCII forms.
        let normalized = text.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return .unset }

        var body = normalized
        for symbol in ["¥", "\\", "円"] { body = body.replacingOccurrences(of: symbol, with: "") }
        body = body.replacingOccurrences(of: " ", with: "")
        if body.hasPrefix("-") || body.hasPrefix("−") {
            return body.dropFirst().allSatisfy(Self.isAmountCharacter) ? .invalid(.notPositive) : .invalid(.notWholeYen)
        }
        guard !body.isEmpty, body.allSatisfy(Self.isAmountCharacter), body.first != "," else {
            return .invalid(.notWholeYen)
        }
        let digits = body.filter { $0 != "," }
        guard !digits.isEmpty else { return .invalid(.notWholeYen) }
        // Leading zeros do not count towards the length check.
        let significant = digits.drop(while: { $0 == "0" })
        if significant.count > String(maximumYen).count { return .invalid(.tooLarge) }
        return validated(Int(significant) ?? 0)
    }

    private static func isAmountCharacter(_ c: Character) -> Bool {
        c == "," || (c.isASCII && c.isNumber)
    }

    /// The amount when valid.
    public var yen: Int? {
        if case .yen(let yen) = self { yen } else { nil }
    }
}

// MARK: - Spend

public enum MonthSpend {
    /// S for a month: the sum of its expenses' totals, exactly as the ledger adds them
    /// (`MonthSummary.totalYen`), refunds and negative totals included.
    /// Nil if the sum does not fit in `Int`, instead of trapping.
    public static func total(_ items: [some LedgerItem]) -> Int? {
        var sum = 0
        for item in items {
            let (next, overflow) = sum.addingReportingOverflow(item.totalYen)
            if overflow { return nil }
            sum = next
        }
        return sum
    }
}

// MARK: - Summary

/// Budget against recorded spend for one month.
public struct BudgetSummary: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// No budget: show the setup prompt.
        case unset
        /// The budget value cannot be used; treat like unset, and say why if it was typed.
        case invalid(MonthlyBudget.Problem)
        /// Spend or remaining is outside the range whole-yen math can hold. Only reachable with
        /// absurd data; the screen shows the spend without budget figures.
        case outOfRange
        /// A budget with figures below.
        case active
    }

    public let month: LedgerMonth
    public let status: Status
    /// S, as the ledger totals it. Nil only when it does not fit in `Int`.
    public let spentYen: Int?
    /// B, when the budget is valid.
    public let budgetYen: Int?
    /// R = B − S, signed. Nil unless `status == .active`.
    public let remainingYen: Int?
    /// Suggested spending for the rest of this week. Only for the current Tokyo month and an
    /// active budget; nil for past and future months.
    public let weeklyAllowance: WeeklyAllowance?

    /// - Parameters:
    ///   - month: the month shown.
    ///   - budget: its budget.
    ///   - items: the month's saved expenses (the same ones the ledger lists for it).
    ///   - now: the current moment; injected for tests.
    ///   - calendar: injected for tests; defaults to Gregorian Asia/Tokyo.
    public init(month: LedgerMonth, budget: MonthlyBudget, items: [some LedgerItem],
                now: Date, calendar: Calendar = .kakeibo) {
        self.init(month: month, budget: budget, spentYen: MonthSpend.total(items), now: now, calendar: calendar)
    }

    public init(month: LedgerMonth, budget: MonthlyBudget, spentYen: Int?,
                now: Date, calendar: Calendar = .kakeibo) {
        self.month = month
        self.spentYen = spentYen
        self.budgetYen = budget.yen

        switch budget {
        case .unset:
            status = .unset
            remainingYen = nil
            weeklyAllowance = nil
            return
        case .invalid(let problem):
            status = .invalid(problem)
            remainingYen = nil
            weeklyAllowance = nil
            return
        case .yen(let b):
            // Defensive: a `.yen` made directly (not through `validated`) is checked here too.
            if case .invalid(let problem) = MonthlyBudget.validated(b) {
                status = .invalid(problem)
                remainingYen = nil
                weeklyAllowance = nil
                return
            }
            guard let s = spentYen else {
                status = .outOfRange
                remainingYen = nil
                weeklyAllowance = nil
                return
            }
            let (r, overflow) = b.subtractingReportingOverflow(s)
            guard !overflow else {
                status = .outOfRange
                remainingYen = nil
                weeklyAllowance = nil
                return
            }
            status = .active
            remainingYen = r
            weeklyAllowance = WeeklyAllowance(month: month, remainingYen: r, now: now, calendar: calendar)
        }
    }

    /// True when spend is above the budget (R < 0).
    public var isOverBudget: Bool { (remainingYen ?? 0) < 0 }

    /// How much spend is above the budget: −R when R < 0, else 0. Nil unless active.
    public var overspentYen: Int? {
        remainingYen.map { $0 < 0 ? -$0 : 0 }
    }

    /// Whole percent of the budget spent, not clamped (130 when over budget), rounded down;
    /// 0 or less when refunds outweigh spend. Nil unless active.
    public var percentSpent: Int? {
        guard status == .active, let s = spentYen, let b = budgetYen else { return nil }
        // floor(S × 100 / B) without overflow: S = qB + r, so S × 100 / B = 100q + 100r / B.
        let q = s / b, r = s % b
        let (hundredQ, overflow) = q.multipliedReportingOverflow(by: 100)
        if overflow { return s > 0 ? Int.max : Int.min }
        var percent = hundredQ + (r * 100) / b   // |r| < B ≤ 999,999,999, so r × 100 fits
        // Swift division truncates toward zero; round down for negative spend.
        if r < 0, (r * 100) % b != 0 { percent -= 1 }
        return percent
    }

    /// Share of the budget spent, for the progress bar only: clamped to 0...1.
    /// The displayed total and percentage are never clamped.
    public var progressFraction: Double? {
        guard status == .active, let s = spentYen, let b = budgetYen else { return nil }
        return min(max(Double(s) / Double(b), 0), 1)
    }
}

// MARK: - Weekly allowance

/// "Available this week": a suggestion for the rest of the current week, spreading what is
/// left of the month evenly over its remaining days. Not a separate cap: there is no rollover
/// and this week's spend is not subtracted again (it is already in S).
public struct WeeklyAllowance: Sendable, Equatable {
    /// floor(max(R, 0) × W / D), whole yen.
    public let yen: Int
    /// D: days from today through the last day of the month, today included.
    public let daysLeftInMonth: Int
    /// W: days from today through Sunday or the month's last day, whichever is first, today included.
    public let daysLeftInWeek: Int
    /// Today, `yyyy-MM-dd` in Tokyo: the first day the suggestion covers.
    public let fromDayKey: String
    /// The last day it covers: Sunday, or the month's last day.
    public let throughDayKey: String

    /// Nil unless `now` falls in `month` (Tokyo): past and future months have no live allowance.
    public init?(month: LedgerMonth, remainingYen: Int, now: Date, calendar: Calendar = .kakeibo) {
        let today = calendar.dateComponents([.year, .month, .day, .weekday], from: now)
        guard let year = today.year, let monthNumber = today.month, let day = today.day,
              let weekday = today.weekday,
              year == month.year, monthNumber == month.month,
              let monthDays = calendar.range(of: .day, in: .month, for: now)?.count
        else { return nil }

        let d = monthDays - day + 1
        // Gregorian weekday: 1 Sunday ... 7 Saturday. Days through Sunday, today included:
        // Monday 7, Tuesday 6, ... Saturday 2, Sunday 1.
        let throughSunday = (8 - weekday) % 7 + 1
        let w = min(throughSunday, d)

        daysLeftInMonth = d
        daysLeftInWeek = w
        yen = Self.share(of: max(remainingYen, 0), days: w, of: d)
        fromDayKey = String(format: "%04d-%02d-%02d", year, monthNumber, day)
        throughDayKey = String(format: "%04d-%02d-%02d", year, monthNumber, day + w - 1)
    }

    /// floor(amount × w / d) for amount ≥ 0 and 1 ≤ w ≤ d, without overflow:
    /// amount = qd + r, so amount × w / d = qw + rw / d, and qw ≤ amount, rw < d².
    static func share(of amount: Int, days w: Int, of d: Int) -> Int {
        let q = amount / d, r = amount % d
        return q * w + (r * w) / d
    }
}
