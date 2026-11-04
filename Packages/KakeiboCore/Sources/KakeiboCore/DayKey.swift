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
}
