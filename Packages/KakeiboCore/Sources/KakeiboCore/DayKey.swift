import Foundation

/// Helpers for `dayKey` strings (`yyyy-MM-dd`, Asia/Tokyo).
public enum DayKey {
    /// True when `value` is exactly `yyyy-MM-dd` and a real calendar date.
    public static func isValid(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard value.count == 10, parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return false }
        return YMD(year: year, month: month, day: day).isValid
    }

    /// The `dayKey` for a moment in time, in Asia/Tokyo.
    public static func make(from date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    /// Noon in Asia/Tokyo on the day, for date pickers. Nil when `value` is not a valid dayKey.
    public static func date(from value: String) -> Date? {
        guard isValid(value) else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// The month part, `yyyy-MM`.
    public static func month(of value: String) -> String { String(value.prefix(7)) }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = KakeiboCore.timeZone
        return calendar
    }()
}
