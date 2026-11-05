import Foundation
import KakeiboCore
import SwiftUI

/// Dates and labels for the ledger, in the app's language and Asia/Tokyo.
enum LedgerFormat {
    /// The language the app is showing (follows the system, limited to ja and en).
    static var language: AppLanguage {
        Bundle.main.preferredLocalizations.first?.hasPrefix("ja") == true ? .ja : .en
    }

    /// "¥1,234" in English, "1,234円" in Japanese.
    static func yen(_ amount: Int) -> String {
        Yen.format(amount, for: language)
    }

    /// "November 2026" or "2026年11月".
    static func monthTitle(_ month: LedgerMonth) -> String {
        formatter(template: "yMMMM").string(from: month.firstDay)
    }

    /// "October" or "10月", for "October ¥178,180".
    static func monthName(_ month: LedgerMonth) -> String {
        formatter(template: "MMMM").string(from: month.firstDay)
    }

    /// "令和8年11月 · Reiwa 8" in English, "令和8年11月" in Japanese.
    static func eraSubtitle(_ month: LedgerMonth) -> String {
        let era = JapaneseEra.label(for: month)
        return language == .ja ? era : "\(era) · \(JapaneseEra.englishYear(for: month))"
    }

    /// "Tue, Nov 3 · 火" in English, "11月3日(火)" in Japanese.
    static func dayTitle(_ dayKey: String) -> String {
        guard let date = DayKey.date(from: dayKey) else { return dayKey }
        if language == .ja {
            return formatter(template: "MMMdEEE").string(from: date)
        }
        return formatter(template: "EEEMMMd").string(from: date) + " · " + japaneseWeekday.string(from: date)
    }

    /// "Thu, Nov 5" in English, "11月5日(木)" in Japanese.
    static func shortDay(_ dayKey: String) -> String {
        guard let date = DayKey.date(from: dayKey) else { return dayKey }
        return formatter(template: language == .ja ? "MMMdEEE" : "EEEMMMd").string(from: date)
    }

    private static func formatter(template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .ja ? "ja_JP" : "en_US")
        formatter.timeZone = KakeiboCore.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private static let japaneseWeekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = KakeiboCore.timeZone
        formatter.dateFormat = "EEEEE"   // 土
        return formatter
    }()
}

extension PaymentMethod {
    /// Short name for ledger rows, from Core: `交通系IC` / `IC card`.
    var shortLabel: String { displayName(for: LedgerFormat.language) }

    /// Both languages for pickers, from Core: `現金 · Cash` / `Cash · 現金`.
    var label: String { pairedName(for: LedgerFormat.language) }
}
