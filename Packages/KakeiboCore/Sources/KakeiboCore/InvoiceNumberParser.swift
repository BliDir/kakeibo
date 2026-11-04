import Foundation

/// Reads the qualified invoice registration number (登録番号): `T` + 13 digits.
///
/// - Hyphens and spaces between digits are tolerated (`T1234-5678-9012-3`).
/// - A number on a line labelled 登録番号, 登録No or 適格請求書 wins over one elsewhere.
/// - On a labelled line, OCR slips are forgiven: the `T` may be missing
///   (`登録番号 1234567890123`, as Vision often reads it) or read as a look-alike (丁, Т, ㄒ, †),
///   and the number may sit on the line after a bare label.
/// - Without a label, only a real `T` + 13 digits counts: JAN barcodes are 13 digits too.
public enum InvoiceNumberParser {
    public struct Result: Sendable, Equatable {
        /// `T` + 13 digits, no separators.
        public var invoiceNumber: String
        /// `high` on a labelled line, `medium` otherwise.
        public var confidence: Confidence
    }

    public static func parse(lines: [String]) -> Result? {
        var fallback: Result?
        for (index, line) in lines.enumerated() {
            if isLabelled(line) {
                if let number = labelledNumber(in: line) {
                    return Result(invoiceNumber: number, confidence: .high)
                }
                // A bare label: the number is on the next line.
                if !line.contains(where: \.isNumber), index + 1 < lines.count,
                   let number = labelledNumber(in: lines[index + 1]) {
                    return Result(invoiceNumber: number, confidence: .high)
                }
            }
            if fallback == nil, let number = number(in: line) {
                fallback = Result(invoiceNumber: number, confidence: .medium)
            }
        }
        return fallback
    }

    /// A strict `T` + 13 digits anywhere on a line.
    static func number(in line: String) -> String? {
        digits(matching: strictPattern, in: line)
    }

    /// 13 digits on a labelled line, with a `T`, a look-alike, or nothing in front.
    static func labelledNumber(in line: String) -> String? {
        digits(matching: lenientPattern, in: line)
    }

    private static func digits(matching pattern: NSRegularExpression, in line: String) -> String? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = pattern.firstMatch(in: line, range: range),
              let r = Range(match.range(at: 1), in: line) else { return nil }
        let digits = line[r].filter(\.isNumber)
        return digits.count == 13 ? "T" + digits : nil
    }

    private static func isLabelled(_ line: String) -> Bool {
        let upper = line.uppercased()
        return labels.contains { upper.contains($0) }
    }

    private static let labels = ["登録番号", "登録NO", "適格請求書"]

    /// T, then 13 digits with optional single hyphens or spaces between them, then no further digit.
    private static let strictPattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z])T\s*[-:]?\s*(\d(?:[\s-]?\d){12})(?![\d])"#
    )

    /// As above, but the T may be missing or one of its OCR look-alikes, and the digits must not
    /// continue a longer number.
    private static let lenientPattern = try! NSRegularExpression(
        pattern: #"(?:(?<![A-Za-z])[T丁Тㄒ†]\s*[-:]?\s*)?(?<![\d])(\d(?:[\s-]?\d){12})(?![\d])"#
    )
}
