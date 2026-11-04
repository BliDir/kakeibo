import Foundation

/// Yen formatting. Money is whole yen in `Int` everywhere.
public enum Yen {
    /// Formats whole yen with grouping, independent of the device locale.
    /// Use this for files and anything that must not change with the UI language.
    ///
    ///     Yen.format(1234)  // "¥1,234"
    ///     Yen.format(-120)  // "-¥120" (discount)
    public static func format(_ amount: Int) -> String {
        (amount < 0 ? "-¥" : "¥") + grouped(amount)
    }

    /// Formats whole yen the way the UI language writes it.
    ///
    ///     Yen.format(1234, for: .en)  // "¥1,234"
    ///     Yen.format(1234, for: .ja)  // "1,234円"
    ///     Yen.format(-120, for: .ja)  // "-120円"
    public static func format(_ amount: Int, for language: AppLanguage) -> String {
        switch language {
        case .en: format(amount)
        case .ja: (amount < 0 ? "-" : "") + grouped(amount) + "円"
        }
    }

    /// The symbol an amount field shows, and on which side: `¥` before in English, `円` after in Japanese.
    public static func fieldSymbol(for language: AppLanguage) -> (symbol: String, isPrefix: Bool) {
        language == .ja ? ("円", false) : ("¥", true)
    }

    private static func grouped(_ amount: Int) -> String {
        let digits = String(amount.magnitude)
        var grouped = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 {
                grouped.append(",")
            }
            grouped.append(digit)
        }
        return grouped
    }
}
