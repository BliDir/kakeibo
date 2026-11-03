import Foundation

/// Reads consumption tax by rate from normalized receipt lines.
///
/// A tax line has 消費税, 内税, 外税, 税額 or 税等 after any 対象, or a bare 税 next to a rate.
/// 税込, 税抜, 非課税, 免税 and 税率 do not count, nor does a bare 税 on a 対象 line. The amount is the first one after the tax word,
/// so `(10%対象 ¥1,100 内税 ¥100)` gives 100, not the taxable amount.
///
/// Rate: 10% or 標準 → `tax10Yen`; 8% or 軽減 → `tax8Yen`. A line with no rate goes to
/// `tax10Yen`, but only when no line names a rate (such lines are usually a grand tax total).
/// A line naming both rates (`内税 10% ¥90 8% ¥37`) is split at each rate.
public enum TaxExtractor {
    public struct Result: Sendable, Equatable {
        public var tax10Yen: Int?
        public var tax8Yen: Int?
        /// `high` when a line named the rate, `medium` for a no-rate line read as 10%.
        public var confidence: Confidence
    }

    /// - Parameter totalYen: the receipt total, if known. Tax amounts at or above it are ignored.
    public static func extract(lines: [String], totalYen: Int? = nil) -> Result? {
        var rated10: [Int] = []
        var rated8: [Int] = []
        var unrated: [Int] = []

        func accept(_ amount: Int) -> Bool {
            amount >= 0 && (totalYen.map { amount < $0 } ?? true)
        }

        for line in lines {
            guard let keyword = taxKeywordStart(in: line) else { continue }
            let afterKeyword = String(line[keyword...])
            let markers = rateMarkers(in: line)

            if markers.contains(where: { $0.rate == .ten }), markers.contains(where: { $0.rate == .eight }) {
                // Both rates on one line: the first amount after each rate marker.
                for marker in markers {
                    let tail = String(line[marker.end...])
                    guard let amount = TotalExtractor.amounts(in: tail).first, accept(amount) else { continue }
                    marker.rate == .ten ? rated10.append(amount) : rated8.append(amount)
                }
                continue
            }

            guard let amount = TotalExtractor.amounts(in: afterKeyword).first, accept(amount) else { continue }
            switch markers.first?.rate {
            case .ten: rated10.append(amount)
            case .eight: rated8.append(amount)
            case nil: unrated.append(amount)
            }
        }

        if !rated10.isEmpty || !rated8.isEmpty {
            return Result(tax10Yen: rated10.first, tax8Yen: rated8.first, confidence: .high)
        }
        if let amount = unrated.first {
            return Result(tax10Yen: amount, tax8Yen: nil, confidence: .medium)
        }
        return nil
    }

    // MARK: - Keywords

    private static let taxWords = ["消費税", "内税", "外税", "税額", "税等"]
    /// Words containing 税 that are not a tax amount.
    private static let notTaxWords = ["税込", "税抜", "非課税", "免税", "税率"]

    /// Where the tax word starts. An explicit tax word wins over a bare 税 next to a rate.
    ///
    /// Only tax words after the last 対象 count: in `外税8%対象 ¥356` the amount is the
    /// taxable base, while in `(10%対象 ¥1,100 内税 ¥100)` the tax word follows 対象.
    private static func taxKeywordStart(in line: String) -> String.Index? {
        let searchStart = line.ranges(of: "対象").last?.upperBound ?? line.startIndex
        let explicit = taxWords.compactMap { line[searchStart...].range(of: $0)?.lowerBound }.min()
        if let explicit { return explicit }

        var masked = line
        for word in notTaxWords {
            masked = masked.replacingOccurrences(of: word, with: String(repeating: "_", count: word.count))
        }
        // A bare 税 on a taxable-base line (`標準税率対象 ¥1,000`) is not a tax amount.
        guard !line.contains("対象"), !rateMarkers(in: line).isEmpty,
              let bare = masked.firstIndex(of: "税") else { return nil }
        // Same character offset in the original line, since masking keeps lengths.
        return line.index(line.startIndex, offsetBy: masked.distance(from: masked.startIndex, to: bare))
    }

    private enum Rate { case ten, eight }

    private static func rateMarkers(in line: String) -> [(rate: Rate, end: String.Index)] {
        let range = NSRange(line.startIndex..., in: line)
        return ratePattern.matches(in: line, range: range).compactMap { match in
            guard let r = Range(match.range, in: line) else { return nil }
            let text = line[r]
            let rate: Rate = (text.hasPrefix("1") || text == "標準") ? .ten : .eight
            return (rate, r.upperBound)
        }
    }

    private static let ratePattern = try! NSRegularExpression(pattern: #"(?<!\d)(?:10|8)\s*%|標準|軽減"#)
}
