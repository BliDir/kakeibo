import Foundation

/// Reads the qualified invoice registration number (登録番号): `T` + 13 digits.
///
/// Hyphens and spaces between digits are tolerated (`T1234-5678-9012-3`).
/// A number on a line with 登録番号 or 登録No wins over one elsewhere.
public enum InvoiceNumberParser {
    public struct Result: Sendable, Equatable {
        /// `T` + 13 digits, no separators.
        public var invoiceNumber: String
        /// `high` on a 登録番号 line, `medium` otherwise.
        public var confidence: Confidence
    }

    public static func parse(lines: [String]) -> Result? {
        var fallback: Result?
        for line in lines {
            guard let number = number(in: line) else { continue }
            let labelled = labels.contains { line.uppercased().contains($0) }
            if labelled { return Result(invoiceNumber: number, confidence: .high) }
            if fallback == nil { fallback = Result(invoiceNumber: number, confidence: .medium) }
        }
        return fallback
    }

    static func number(in line: String) -> String? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = pattern.firstMatch(in: line, range: range),
              let r = Range(match.range(at: 1), in: line) else { return nil }
        let digits = line[r].filter(\.isNumber)
        return digits.count == 13 ? "T" + digits : nil
    }

    private static let labels = ["登録番号", "登録NO", "登録NO.", "適格請求書"]

    /// T, then 13 digits with optional single hyphens or spaces between them, then no further digit.
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z])T\s*[-:]?\s*(\d(?:[\s-]?\d){12})(?![\d])"#
    )
}
