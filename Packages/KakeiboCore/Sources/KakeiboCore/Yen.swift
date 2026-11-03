import Foundation

/// Yen formatting. Money is whole yen in `Int` everywhere.
public enum Yen {
    /// Formats whole yen with grouping, independent of the device locale.
    ///
    ///     Yen.format(1234)  // "¥1,234"
    ///     Yen.format(-120)  // "-¥120" (discount)
    public static func format(_ amount: Int) -> String {
        let digits = String(amount.magnitude)
        var grouped = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 {
                grouped.append(",")
            }
            grouped.append(digit)
        }
        return (amount < 0 ? "-¥" : "¥") + grouped
    }
}
