import Foundation

/// Namespace for the Kakeibo domain layer.
/// Parser, normalizer, era dates, category rules and CSV writer land here in later tickets.
public enum KakeiboCore {
    /// Time zone used for every `dayKey` (`yyyy-MM-dd`).
    public static let timeZone = TimeZone(identifier: "Asia/Tokyo")!
}
