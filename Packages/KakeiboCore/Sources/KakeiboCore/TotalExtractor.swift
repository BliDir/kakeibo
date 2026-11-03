import Foundation

/// Finds the amount actually paid on a receipt.
///
/// Input lines must already be normalized by `TextNormalizer`.
///
/// How the total is chosen:
/// 1. Lines with a total keyword (合計, お買上, 御買上, ご請求額, TOTAL) are candidates.
///    The amount is the last one on the line, or on the next line when the keyword line has none.
/// 2. Lines about cash handed over, change, item counts, points, balances, taxable bases
///    (`…%対象`, `対象額`), tax amounts and discounts are never candidates.
/// 3. When both お預り and お釣り exist, a candidate equal to お預り − お釣り wins.
///    Otherwise the largest candidate wins.
/// 4. With no total line, 小計 is used, then お預り − お釣り.
///
/// Confidence:
/// - `high`: found by keyword and an arithmetic check passes
///   (change, subtotal + external tax, or item sum).
/// - `medium`: found by keyword alone, or a fallback whose arithmetic check passes.
/// - `low`: a fallback with no check, or a keyword total that contradicts お預り − お釣り.
public enum TotalExtractor {
    public struct Result: Sendable, Equatable {
        public var totalYen: Int
        public var confidence: Confidence
        public var source: Source
        /// The arithmetic check that confirmed the total, if any.
        public var check: Check?
        public var subtotalYen: Int?
        public var tenderedYen: Int?
        public var changeYen: Int?
    }

    public enum Source: String, Sendable, Equatable {
        /// A line with a total keyword.
        case totalLine
        /// 小計, because no total line was found.
        case subtotalFallback
        /// お預り − お釣り, because neither a total nor a subtotal line was found.
        case changeFallback
    }

    public enum Check: String, Sendable, Equatable {
        /// お預り − お釣り = total.
        case change
        /// 小計 + external tax (外税) = total.
        case subtotalPlusTax
        /// Sum of item prices = total.
        case itemSum
    }

    /// Largest amount accepted as a receipt total. Anything bigger is a misread number.
    public static let maximumYen = 10_000_000

    /// - Parameters:
    ///   - lines: normalized receipt lines, top to bottom.
    ///   - itemPrices: item line prices if already parsed (discounts negative). Used only for the item-sum check.
    public static func extract(lines: [String], itemPrices: [Int] = []) -> Result? {
        let scan = Scan(lines: lines)

        let changeTotals = Set(scan.tendered.flatMap { tendered in
            scan.change.map { tendered - $0 }
        }.filter { $0 > 0 })
        let hasChangeCheck = !changeTotals.isEmpty
        let subtotal = scan.subtotals.last

        func passingCheck(for total: Int) -> Check? {
            if changeTotals.contains(total) { return .change }
            if let subtotal, !scan.externalTaxes.isEmpty,
               subtotal + scan.externalTaxes.reduce(0, +) == total {
                return .subtotalPlusTax
            }
            if !itemPrices.isEmpty, itemPrices.reduce(0, +) == total { return .itemSum }
            return nil
        }

        func result(_ total: Int, _ source: Source, _ confidence: Confidence, _ check: Check?) -> Result {
            Result(
                totalYen: total,
                confidence: confidence,
                source: source,
                check: check,
                subtotalYen: subtotal,
                tenderedYen: scan.tendered.first,
                changeYen: scan.change.first
            )
        }

        if !scan.totals.isEmpty {
            let total = scan.totals.first(where: changeTotals.contains) ?? scan.totals.max()!
            if let check = passingCheck(for: total) {
                return result(total, .totalLine, .high, check)
            }
            // A change check that exists but disagrees means one of the numbers is misread.
            return result(total, .totalLine, hasChangeCheck ? .low : .medium, nil)
        }

        if let subtotal {
            let check = passingCheck(for: subtotal)
            return result(subtotal, .subtotalFallback, check == nil ? .low : .medium, check)
        }

        if let total = changeTotals.max() {
            return result(total, .changeFallback, .low, nil)
        }
        return nil
    }

    // MARK: - Line scan

    private struct Scan {
        var totals: [Int] = []
        var subtotals: [Int] = []
        var tendered: [Int] = []
        var change: [Int] = []
        var externalTaxes: [Int] = []

        init(lines: [String]) {
            for (index, line) in lines.enumerated() {
                let kind = LineKind(line)
                guard kind != .other else { continue }
                guard let amount = amount(on: index, in: lines) else { continue }
                switch kind {
                case .total: totals.append(amount)
                case .subtotal: subtotals.append(amount)
                case .tendered: tendered.append(amount)
                case .change: change.append(amount)
                case .externalTax: externalTaxes.append(amount)
                case .excluded, .other: break
                }
            }
        }

        /// The last amount on the line, or on the next line when that line is just an amount.
        private func amount(on index: Int, in lines: [String]) -> Int? {
            if let amount = TotalExtractor.amounts(in: lines[index]).last { return amount }
            let next = index + 1
            guard next < lines.count, LineKind(lines[next]) == .other else { return nil }
            return TotalExtractor.amounts(in: lines[next]).last
        }
    }

    private enum LineKind: Equatable {
        case total, subtotal, tendered, change, externalTax, excluded, other

        init(_ line: String) {
            let upper = line.uppercased()
            func has(_ words: [String]) -> Bool { words.contains { upper.contains($0) } }

            // Order matters: a line such as お預り合計 or 外税8%対象 must not become a total.
            if has(Keywords.change) { self = .change }
            else if has(Keywords.tendered) { self = .tendered }
            else if has(Keywords.neverTotal) {
                self = .excluded
            } else if has(Keywords.tax) && !has(Keywords.taxIncluded) {
                self = has(Keywords.internalTax) ? .excluded : .externalTax
            } else if has(Keywords.subtotal) { self = .subtotal }
            else if has(Keywords.total) { self = .total }
            else { self = .other }
        }
    }

    private enum Keywords {
        static let total = ["合計", "お買上", "お買い上げ", "御買上", "ご請求額", "ご請求金額", "御請求額", "TOTAL"]
        static let subtotal = ["小計", "SUBTOTAL", "SUB TOTAL"]
        static let tendered = ["お預り", "お預かり", "預り", "預かり", "オアズカリ", "現金"]
        static let change = ["お釣り", "お釣", "釣銭", "釣り銭", "おつり", "オツリ", "CHANGE"]
        /// 対象 covers taxable-base lines: `10%対象 ¥1,000`, `外税対象額 ¥1,000`.
        static let neverTotal = ["点数", "ポイント", "残高", "値引", "割引", "クーポン", "対象"]
        static let tax = ["消費税", "外税", "内税", "税額", "税等"]
        static let taxIncluded = ["税込"]
        static let internalTax = ["内税", "内消費税", "内 消費税", "(内"]
    }

    // MARK: - Reading amounts

    /// Yen amounts on a line, left to right. Times, dates, percentages,
    /// item counts and quantities are removed first.
    static func amounts(in line: String) -> [Int] {
        var s = line
        for pattern in ignoredNumbers {
            s = pattern.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }
        let range = NSRange(s.startIndex..., in: s)
        return amountPattern.matches(in: s, range: range).compactMap { match in
            guard let digitsRange = Range(match.range(at: 2), in: s) else { return nil }
            let digits = s[digitsRange].replacingOccurrences(of: ",", with: "")
            guard let value = Int(digits), value <= maximumYen else { return nil }
            let negative = match.range(at: 1).length > 0
            return negative ? -value : value
        }
    }

    private static let ignoredNumbers: [NSRegularExpression] = [
        #"\d{1,2}:\d{2}(?::\d{2})?"#,                 // 14:05, 14:05:33
        #"\d{2,4}[/.\-]\d{1,2}[/.\-]\d{1,2}"#,          // 2026/11/03
        #"\d+\s*[年月日]"#,                              // 2026年11月3日
        #"\d+(?:\.\d+)?\s*%"#,                          // 10%, 8 %
        #"\d+\s*(?:点|個|コ|品|枚)"#,                    // 3点
        #"[x×*]\s*\d+"#,                                // x2
        #"@\s*¥?\s*\d[\d,]*"#,                          // @120
    ].map { try! NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    /// Group 1: minus sign (`-` or ▲), group 2: digits with optional thousands commas.
    private static let amountPattern = try! NSRegularExpression(
        pattern: #"([-▲△]\s*)?¥?\s*(?<![\d,])(\d{1,3}(?:,\d{3})+|\d+)(?![\d,])"#
    )
}
