import Foundation
import KakeiboCore

/// The instructions and prompt for the on-device model.
public enum RefinerPrompt {
    public static let instructions = """
    You read Japanese shop receipts (レシート) from OCR text and return the fields asked for.
    Rules:
    - The total is the amount paid: the line with 合計, お買上, 御買上 or ご請求額.
      Never use お預り or お預かり (cash handed over), お釣り (change), 小計 when a 合計 exists,
      ポイント, 残高 or lines with 対象 (taxable amounts).
    - When お預り and お釣り both appear, お預り minus お釣り equals the total.
    - Dates may use the Japanese era: 令和N年 is the year 2018 + N (令和8年 = 2026), and R8.11.3 means 令和8年11月3日.
      Return dates as yyyy-MM-dd.
    - Items marked ※ or ★ are taxed at the reduced 8% rate.
    - Discounts (値引, 割引) are items with a negative price.
    - Amounts are whole yen. Ignore commas and the ¥ sign.
    - For every item, give the Japanese name as printed and a short natural English name.
    - Leave a field empty when the receipt does not show it. Do not guess.
    """

    static func make(lines: [String], draft: ReceiptDraft) -> String {
        var parts = ["Receipt OCR text:", lines.joined(separator: "\n"), "", "A rule-based parser already found:"]
        func add(_ label: String, _ value: CustomStringConvertible?) {
            parts.append("- \(label): \(value.map { "\($0)" } ?? "not found")")
        }
        add("store", draft.storeName)
        add("date", draft.dayKey)
        add("total", draft.totalYen)
        add("tax 10%", draft.tax10Yen)
        add("tax 8%", draft.tax8Yen)
        add("payment", draft.confidence(for: .payment) == .low ? nil : draft.payment?.rawValue)
        parts.append("")
        parts.append("Check these against the text, fill in what is missing, and list every item line.")
        return parts.joined(separator: "\n")
    }
}
