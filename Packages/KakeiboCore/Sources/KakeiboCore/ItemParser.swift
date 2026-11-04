import Foundation

/// Reads item lines from normalized receipt lines, for iPhones without the on-device model.
///
/// - Item rows are the lines above 小計/合計 that end in a price (`おにぎり鮭 ※ ¥160`).
///   Header lines that also end in digits (dates, times, TEL, レジ No., addresses, 登録番号,
///   unit prices) are skipped.
/// - Quantity lines (`2コ × 198`, `3点 × @98 ¥294`) fold into the item above. A name printed
///   without a price takes its price from the quantity line below it.
/// - Discounts (値引, 割引, クーポン) become negative items right after the item they reduce,
///   with that item's tax rate.
/// - ※, ★ or a standalone 軽 mark the 8% reduced rate. A leading 軽 joined to the name by the
///   normalizer (`軽牛乳`) is not recognised, because it cannot be told apart from words like 軽食.
public enum ItemParser {
    public static func parse(lines: [String]) -> [LineItemDraft] {
        var items: [LineItemDraft] = []
        /// A name printed on its own line, waiting for a quantity line with its price.
        var pendingName: (name: String, reduced: Bool)?

        for line in itemRegion(lines) {
            if isHeaderLine(line) {
                pendingName = nil
                continue
            }
            let reduced = isReducedRate(line)

            if let quantity = Quantity(line) {
                if let pending = pendingName {
                    items.append(LineItemDraft(name: pending.name, priceYen: quantity.lineTotal,
                                               isReducedRate: pending.reduced || reduced))
                    pendingName = nil
                } else if var last = items.last, last.priceYen > 0 {
                    // The item above already shows its total; keep the larger of the two readings.
                    last.priceYen = max(last.priceYen, quantity.lineTotal)
                    items[items.count - 1] = last
                }
                continue
            }

            if isDiscount(line) {
                guard let amount = trailingPrice(line)?.value, amount != 0 else { continue }
                let above = items.last
                items.append(LineItemDraft(
                    name: cleanName(line, removing: trailingPrice(line)?.range) ?? "値引",
                    priceYen: -abs(amount),
                    isReducedRate: above?.isReducedRate ?? reduced
                ))
                pendingName = nil
                continue
            }

            guard let price = trailingPrice(line) else {
                // Letters but no price: maybe a name whose price is on the next line.
                if let name = cleanName(line, removing: nil), name.unicodeScalars.contains(where: CharacterSet.letters.contains) {
                    pendingName = (name, reduced)
                }
                continue
            }
            guard price.value > 0, let name = cleanName(line, removing: price.range) else { continue }
            items.append(LineItemDraft(name: name, priceYen: price.value, isReducedRate: reduced))
            pendingName = nil
        }
        return items
    }

    // MARK: - Region

    /// Lines above the first subtotal or total line; all lines when there is none.
    static func itemRegion(_ lines: [String]) -> ArraySlice<String> {
        let end = lines.firstIndex { line in
            let upper = line.uppercased()
            return endWords.contains { upper.contains($0) }
        }
        return lines[..<(end ?? lines.endIndex)]
    }

    private static let endWords = ["小計", "合計", "お買上", "御買上", "ご請求", "TOTAL", "お預", "預り", "お釣"]

    // MARK: - Line kinds

    private static let headerWords = [
        "TEL", "電話", "FAX", "〒", "登録番号", "NO.", "NO ", "担当", "責", "領収", "人数", "テーブル",
        "単価", "対象", "消費税", "内税", "外税", "ポイント", "会員", "伝票",
        "取引番号", "取引NO", "レシート番号", "レシートNO",
    ]

    private static let headerPatterns: [NSRegularExpression] = [
        #"\d{1,2}:\d{2}"#,                         // a time
        #"\d+[/.]\d{1,2}[/.]\d{1,2}"#,              // a date
        #"\d+年\d+月|\d+月\d+日"#,                  // a Japanese date
        #"[都道府県].*[市区町村郡]"#,                 // an address
        #"\d+-\d+-?\d*\s*$"#,                       // ends like 1-2-3 (番地) or a phone number
        #"T\d{13}"#,                                // invoice number
        #"レジ\s*(?:\d|NO|#|番号)"#,                  // register number (not レジ袋)
    ].map { try! NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    static func isHeaderLine(_ line: String) -> Bool {
        let upper = line.uppercased()
        if headerWords.contains(where: upper.contains) { return true }
        let range = NSRange(line.startIndex..., in: line)
        return headerPatterns.contains { $0.firstMatch(in: line, range: range) != nil }
    }

    private static let discountWords = ["値引", "割引", "クーポン", "ネビキ"]

    static func isDiscount(_ line: String) -> Bool {
        discountWords.contains(where: line.contains)
    }

    static func isReducedRate(_ line: String) -> Bool {
        if line.contains("※") || line.contains("★") { return true }
        let range = NSRange(line.startIndex..., in: line)
        return standaloneKei.firstMatch(in: line, range: range) != nil
            || keiBeforePrice.firstMatch(in: line, range: range) != nil
    }

    /// 軽 right before the line's price (`牛乳軽 198`, which the normalizer makes of `牛乳 軽 198`).
    private static let keiBeforePrice = try! NSRegularExpression(
        pattern: #"軽\s*¥?\s*(?:\d{1,3}(?:,\d{3})+|\d+)\s*円?\s*$"#
    )

    /// 軽 on its own or right against the price (`198軽`), not inside a word like 軽食.
    private static let standaloneKei = try! NSRegularExpression(
        pattern: #"(?:^|[\s\d¥])軽(?:$|[\s\d¥])"#
    )

    // MARK: - Prices

    struct Price {
        var value: Int
        /// The price text, to cut it out of the name.
        var range: Range<String.Index>
    }

    /// The price at the end of the line: `¥1,320`, `198`, `-100`, `▲30`, `450円`,
    /// optionally followed by a rate mark (`198 ※`, `198軽`).
    ///
    /// Digits right after `:` `/` `-` `.` belong to a time, date or code, not a price.
    /// Without ¥ or 円, values under 10 are counts (`人数 2`), not prices.
    static func trailingPrice(_ line: String) -> Price? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = pricePattern.firstMatch(in: line, range: range),
              let whole = Range(match.range, in: line),
              let digitsRange = Range(match.range(at: 3), in: line),
              let value = Int(line[digitsRange].filter(\.isNumber))
        else { return nil }
        let hasYen = match.range(at: 2).length > 0 || match.range(at: 4).length > 0
        guard hasYen || value >= 10, value <= 1_000_000 else { return nil }
        let negative = match.range(at: 1).length > 0
        return Price(value: negative ? -value : value, range: whole)
    }

    /// Groups: 1 sign, 2 ¥, 3 digits, 4 円.
    private static let pricePattern = try! NSRegularExpression(
        pattern: #"(?<![\d:/\-.,])\s*([-▲△]\s*)?(¥\s*)?(?<![:/.\d,])(\d{1,3}(?:,\d{3})+|\d+)\s*(円)?\s*(?:[※★軽]|外|内)?\s*$"#
    )

    // MARK: - Names

    /// The line without its price and rate marks, or nil when nothing is left.
    static func cleanName(_ line: String, removing priceRange: Range<String.Index>?) -> String? {
        var name = line
        let markedBeforePrice = keiBeforePrice.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        if let priceRange { name.removeSubrange(priceRange) }
        if markedBeforePrice, name.hasSuffix("軽") { name.removeLast() }
        name = name.replacingOccurrences(of: "※", with: "").replacingOccurrences(of: "★", with: "")
        let range = NSRange(name.startIndex..., in: name)
        name = kei.stringByReplacingMatches(in: name, range: range, withTemplate: "")
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private static let kei = try! NSRegularExpression(pattern: #"(?:^|\s)軽(?=$|\s)"#)

    // MARK: - Quantity lines

    /// `2コ × 198`, `2個 x 158 ¥316`, `3点 × @98 ¥294`, `@120 x 2`.
    struct Quantity {
        var count: Int
        var unitYen: Int
        /// The printed line total, or count × unit when none is printed.
        var lineTotal: Int

        init?(_ line: String) {
            let range = NSRange(line.startIndex..., in: line)
            var count: Int?
            var unit: Int?
            var end = 0
            if let m = Quantity.countFirst.firstMatch(in: line, range: range) {
                count = Range(m.range(at: 1), in: line).flatMap { Int(line[$0]) }
                unit = Range(m.range(at: 2), in: line).flatMap { Int(line[$0].filter(\.isNumber)) }
                end = m.range.upperBound
            } else if let m = Quantity.unitFirst.firstMatch(in: line, range: range) {
                unit = Range(m.range(at: 1), in: line).flatMap { Int(line[$0].filter(\.isNumber)) }
                count = Range(m.range(at: 2), in: line).flatMap { Int(line[$0]) }
                end = m.range.upperBound
            }
            guard let count, let unit, count > 0, count < 1_000, unit > 0 else { return nil }
            self.count = count
            unitYen = unit
            // A total printed after the quantity: "3点 × @98 ¥294".
            let rest = String(line[String.Index(utf16Offset: end, in: line)...])
            lineTotal = ItemParser.trailingPrice(rest)?.value ?? count * unit
        }

        private static let countFirst = try! NSRegularExpression(
            pattern: #"(\d+)\s*(?:コ|個|点|本|袋|枚|P|ケ)?\s*[x×*]\s*@?\s*¥?\s*(\d{1,3}(?:,\d{3})+|\d+)"#,
            options: .caseInsensitive
        )
        private static let unitFirst = try! NSRegularExpression(
            pattern: #"@\s*¥?\s*(\d{1,3}(?:,\d{3})+|\d+)\s*[x×*]\s*(\d+)"#,
            options: .caseInsensitive
        )
    }
}
