import Foundation

/// Decides how a receipt was paid from normalized lines.
///
/// 1. Change (お釣り) above ¥0 means cash.
/// 2. Otherwise the first group with a keyword wins, in this order:
///    - `qrPay`: PayPay, 楽天ペイ, d払い, au PAY, メルペイ
///    - `icCard`: Suica, PASMO, ICOCA, iD, QUICPay, nanaco, WAON, 交通系, 電子マネー
///    - `credit`: クレジット, VISA, Master, JCB, AMEX
/// 3. Otherwise cash.
///
/// Point lines (ポイント, POINT) are skipped: cash receipts often show nanaco or WAON points.
public enum PaymentMethodDetector {
    public struct Result: Sendable, Equatable {
        public var payment: PaymentMethod
        /// `high` from a keyword or a cash change line, `low` when cash is only the default.
        public var confidence: Confidence
    }

    public static func detect(lines: [String]) -> Result {
        let relevant = lines.filter { line in
            let upper = line.uppercased()
            return !upper.contains("ポイント") && !upper.contains("POINT")
        }

        if relevant.contains(where: isPositiveChangeLine) {
            return Result(payment: .cash, confidence: .high)
        }
        for (method, patterns) in groups {
            if relevant.contains(where: { line in patterns.contains { $0.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil } }) {
                return Result(payment: method, confidence: .high)
            }
        }
        return Result(payment: .cash, confidence: .low)
    }

    private static func isPositiveChangeLine(_ line: String) -> Bool {
        guard changeWords.contains(where: line.contains) else { return false }
        return TotalExtractor.amounts(in: line).contains { $0 > 0 }
    }

    private static let changeWords = ["お釣り", "お釣", "釣銭", "釣り銭", "おつり", "オツリ"]

    /// Case-insensitive unless noted. Latin keywords must not touch other letters,
    /// so `iD` does not match `ID` inside a word such as `PAID`.
    private static let groups: [(PaymentMethod, [NSRegularExpression])] = [
        (.qrPay, [word("PAYPAY"), any("楽天ペイ"), any("d払"), word(#"AU\s*PAY"#), any("メルペイ")]),
        (.icCard, [word("SUICA"), word("PASMO"), word("ICOCA"), word("iD", caseSensitive: true),
                   word("QUICPAY"), word("NANACO"), word("WAON"), any("交通系"), any("電子マネー")]),
        (.credit, [any("クレジット"), word("VISA"), word("MASTER(?:CARD)?"), word("JCB"),
                   word("AMEX"), word(#"AMERICAN\s*EXPRESS"#)]),
    ]

    private static func word(_ pattern: String, caseSensitive: Bool = false) -> NSRegularExpression {
        try! NSRegularExpression(
            pattern: "(?<![A-Za-z])\(pattern)(?![A-Za-z])",
            options: caseSensitive ? [] : .caseInsensitive
        )
    }

    private static func any(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }
}
