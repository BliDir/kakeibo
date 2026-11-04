import Foundation

/// Reads the receipt's own number (レシートNo., 取引番号, 伝票番号, ...) and the register (レジ) number.
///
/// Unlike the invoice registration number, which is the same on every receipt from a shop,
/// this number identifies one sale, so it tells a second scan of the same receipt from a
/// second visit. Receipt numbers usually restart per register, so the register number is
/// part of the result when printed: `レジ02 No.0012` → `02/0012`.
///
/// Numbers are kept as printed (leading zeros and inner hyphens stay). Compare them with
/// `comparisonKey(_:)`, which ignores leading zeros.
public enum ReceiptNumberParser {
    public struct Result: Sendable, Equatable {
        /// `<register>/<number>` when a register number is printed nearby, otherwise `<number>`.
        public var receiptNumber: String
        /// `high` after a receipt label (レシート, 取引, 伝票), `medium` after a bare `No.`.
        public var confidence: Confidence
    }

    /// - Parameter lines: lines that have already been through `TextNormalizer`.
    public static func parse(lines: [String]) -> Result? {
        guard let (index, number, confidence) = findNumber(in: lines) else { return nil }
        // The register is on the same line or a line next to it.
        let nearby = [index] + [index - 1, index + 1, index - 2, index + 2].filter(lines.indices.contains)
        let register = nearby.lazy.compactMap { firstGroup(of: registerPattern, in: lines[$0]) }.first
        let value = register.map { "\($0)/\(number)" } ?? number
        return Result(receiptNumber: value, confidence: confidence)
    }

    /// The number with each digit group's leading zeros removed, for comparing two receipts:
    /// `02/0012` and `2/12` give the same key. Returns nil when there are no digits.
    public static func comparisonKey(_ receiptNumber: String) -> String? {
        let groups = receiptNumber.split(whereSeparator: { !$0.isASCII || !$0.isNumber }).map { group in
            let trimmed = group.drop(while: { $0 == "0" })
            return trimmed.isEmpty ? "0" : String(trimmed)
        }
        return groups.isEmpty ? nil : groups.joined(separator: "-")
    }

    // MARK: - Finding the number

    private static func findNumber(in lines: [String]) -> (index: Int, number: String, Confidence)? {
        for (index, line) in lines.enumerated() {
            if let number = firstGroup(of: labelledPattern, in: line) {
                return (index, number, .high)
            }
        }
        for (index, line) in lines.enumerated() where !isOtherNumberLine(line) {
            if let number = firstGroup(of: barePattern, in: line) {
                return (index, number, .medium)
            }
        }
        return nil
    }

    /// Lines where a bare `No.` is some other number: member, card, approval, terminal,
    /// store, cashier, phone, or the invoice registration number.
    private static func isOtherNumberLine(_ line: String) -> Bool {
        let upper = line.uppercased()
        return otherNumberWords.contains(where: upper.contains)
    }

    private static let otherNumberWords = [
        "会員", "カード", "CARD", "承認", "端末", "店", "担当", "責", "TEL", "電話", "FAX", "登録",
        "ポイント", "お客様", "口座", "郵便",
    ]

    /// The number: digits, with single hyphens between digit groups.
    private static let number = #"(\d+(?:-\d+)*)"#

    /// レシートNo. / レシート番号 / 取引番号 / 取引No. / 伝票番号 / 伝票No, then the number.
    private static let labelledPattern = regex(
        #"(?:レシート|取引|伝票)\s*(?:NO\.?|番号|#)\s*[:.#]?\s*"# + number + #"(?![\d])"#
    )

    /// A bare `No.1234` (or `NO 1234`) not inside a longer word.
    private static let barePattern = regex(#"(?<![A-Z])NO\.?\s*[:.#]?\s*"# + number + #"(?![\d])"#)

    /// レジ02, レジNo.2, レジ番号 2, レジ#3.
    private static let registerPattern = regex(#"レジ\s*(?:NO\.?|番号|#)?\s*[:.]?\s*(\d{1,4})(?!\d)"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are constants; a failure here is a programming error caught by tests.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func firstGroup(of regex: NSRegularExpression, in line: String) -> String? {
        guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[range])
    }
}
