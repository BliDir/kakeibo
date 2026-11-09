import Foundation

/// Reads item lines from normalized receipt lines, for iPhones without the on-device model.
///
/// - Item rows are the lines above the end of the list (see below) that end in a price (`おにぎり鮭 ※ ¥160`).
///   Header lines that also end in digits (dates, times, TEL, レジ No., addresses, 登録番号,
///   unit prices) are skipped.
/// - Quantity lines (`2コ × 198`, `3点 × @98 ¥294`, AEON `(7個×単98)`, Life `2コX単1080 ¥2,160`)
///   fold into the item above. A name printed without a price takes its price from the quantity
///   line below it, or from a count line (`1点※ ¥270`).
/// - Discounts (値引, 割引, クーポン, 半額, 20%引, 50円引, OFF) become negative items right after
///   the item they reduce, with that item's tax rate.
/// - 7-Eleven marks the reduced rate with `*` right before the price (`*130`). Marks after a
///   price (`490込`, `50非`, `外`, `内`, `▽`) are dropped, and so are leading `◎ ● ○ ◆ ☆` and `▽`.
/// - A price may end in a one-letter tax or category mark after a ¥ (`¥199C` at Seiyu) or in
///   `*`; the mark is dropped. Leading 2–3 digit department codes (`01 テンネンスイ`) are
///   dropped from names.
/// - A name that never gets a price is dropped, and so is a printed ¥0 line: no item is ever ¥0.
///   The item-sum check then flags the items (B-15; B-13 kept such names at ¥0).
/// - A quantity stuck to the end of a name (`天然水新潟県津南60 @118× 2点 ¥236軽`) is taken off
///   the name; the printed total is the price. A bare number glued to a name (`津南60`) is part
///   of it. Separator rows (`=====`, OCR's `ニーニニニ`) are never items.
/// - The list ends at 小計/合計 (and OCR misreads of large 合計, repaired by `TextNormalizer`),
///   and, once an item has been read, at tax, payment and card-slip lines or a line showing the
///   total. No item costs more than the total. `repairShiftedPrices` puts back prices a tilted
///   photo moved one row (B-15).
/// - ※, ★ or a standalone 軽 mark the 8% reduced rate. A leading 軽 joined to the name by the
///   normalizer (`軽牛乳`) is not recognised, because it cannot be told apart from words like 軽食.
public enum ItemParser {
    /// - Parameter totalYen: the receipt total when known. The item list then also ends at a line
    ///   whose amount is the total (`クレジット支払 ¥1,469`), once an item has been read.
    public static func parse(lines: [String], totalYen: Int? = nil) -> [LineItemDraft] {
        var items: [LineItemDraft] = []
        /// A name printed on its own line, waiting for a quantity line with its price. A name that
        /// never gets one is dropped (B-15: no ¥0 items); the item-sum check then flags the items.
        var pendingName: (name: String, reduced: Bool)?

        for line in itemRegion(lines, totalYen: totalYen) {
            if isHeaderLine(line) || isSeparator(line) {
                pendingName = nil
                continue
            }
            let reduced = isReducedRate(line)

            if let quantity = Quantity(line) {
                if let name = quantity.name {
                    // The name and its quantity on one row (`天然水新潟県津南60 @118× 2点 ¥236軽`).
                    items.append(LineItemDraft(name: name, priceYen: quantity.lineTotal, isReducedRate: reduced))
                    pendingName = nil
                } else if let pending = pendingName {
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

            // A count with the price, under a name printed on its own line (`1点※ ¥270`).
            if isCountLine(line), let price = trailingPrice(line), price.value > 0 {
                if let pending = pendingName {
                    items.append(LineItemDraft(name: pending.name, priceYen: price.value,
                                               isReducedRate: pending.reduced || reduced))
                    pendingName = nil
                } else if var last = items.last, last.priceYen > 0 {
                    last.priceYen = max(last.priceYen, price.value)
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
            // A ¥0 line (`迎車料金 ¥0`) adds nothing, and an unpriced name is never given ¥0.
            guard price.value > 0, let name = cleanName(line, removing: price.range) else { continue }
            pendingName = nil
            items.append(LineItemDraft(name: name, priceYen: price.value,
                                       isReducedRate: reduced || hasStarBeforePrice(line)))
        }
        if let totalYen {
            // No single item costs more than the whole receipt.
            items.removeAll { $0.priceYen > totalYen }
        }
        return items
    }

    // MARK: - Shifted prices

    /// B-15: on a tilted photo of tightly printed rows, a run of right-column prices can land one
    /// row up or down from their names. When the items do not add up, this tries moving the prices
    /// of each such run back by one row: the run lies between a name without a price and the row
    /// that took the extra price. A pairing is used only when `accepts` says its items add up
    /// exactly and no price moves onto a header or separator line. Shortest run first.
    public static func repairShiftedPrices(lines: [String], totalYen: Int?,
                                           accepts: ([LineItemDraft]) -> Bool) -> [LineItemDraft]? {
        let regionEnd = itemRegion(lines, totalYen: totalYen).endIndex
        let region = Array(lines[..<regionEnd])
        struct Row { var name: String; var price: Substring? }
        let rows: [Row] = region.map { line in
            guard let price = trailingPrice(line) else { return Row(name: line, price: nil) }
            var name = line
            name.removeSubrange(price.range)
            return Row(name: name.trimmingCharacters(in: .whitespaces), price: line[price.range])
        }
        /// Rows a price can move between: plain item rows (no quantity, count or discount line).
        func movable(_ i: Int) -> Bool {
            let line = region[i]
            return Quantity(line) == nil && !isCountLine(line) && !isDiscount(line)
        }
        func receives(_ i: Int) -> Bool { !isHeaderLine(rows[i].name) && !isSeparator(rows[i].name) && movable(i) }
        func waitingName(_ i: Int) -> Bool {
            rows[i].price == nil && receives(i)
                && rows[i].name.unicodeScalars.contains(where: CharacterSet.letters.contains)
        }

        var candidates: [(length: Int, lines: [String])] = []
        for b in rows.indices where waitingName(b) {
            // Prices one row too high: row i's price printed on row i − 1, for rows a+1 … b.
            var a = b - 1
            while a >= 0, rows[a].price != nil, movable(a) {
                if (a + 1...b).allSatisfy(receives) {
                    var shifted = region
                    shifted[a] = rows[a].name
                    for i in a + 1...b { shifted[i] = rows[i].name + " " + rows[i - 1].price! }
                    candidates.append((b - a, shifted))
                }
                a -= 1
            }
            // Prices one row too low: row i's price printed on row i + 1, for rows b … c−1.
            var c = b + 1
            while c < rows.count, rows[c].price != nil, movable(c) {
                if (b...c - 1).allSatisfy(receives) {
                    var shifted = region
                    shifted[c] = rows[c].name
                    for i in b...c - 1 { shifted[i] = rows[i].name + " " + rows[i + 1].price! }
                    candidates.append((c - b, shifted))
                }
                c += 1
            }
        }
        let tail = Array(lines[regionEnd...])
        for candidate in candidates.sorted(by: { $0.length < $1.length }) {
            let items = parse(lines: candidate.lines + tail, totalYen: totalYen)
            if accepts(items) { return items }
        }
        return nil
    }

    // MARK: - Region

    /// Lines above the first subtotal or total line; all lines when there is none.
    ///
    /// Once an item has been read, the list also ends at tax, payment and card-slip lines
    /// (`対象`, `支払`, `会社名`, …) and at a line whose amount is `totalYen`: OCR can miss or
    /// garble a large 合計 (B-15).
    static func itemRegion(_ lines: [String], totalYen: Int? = nil) -> ArraySlice<String> {
        var itemsStarted = false
        let end = lines.indices.first { index in
            let line = lines[index]
            let upper = line.uppercased()
            if endWords.contains(where: upper.contains) { return true }
            if itemsStarted {
                if endWordsAfterItems.contains(where: upper.contains) { return true }
                if cardSlipCode.firstMatch(in: upper, range: NSRange(upper.startIndex..., in: upper)) != nil { return true }
                if let totalYen, Quantity(line) == nil, trailingPrice(line)?.value == totalYen { return true }
            }
            if !isHeaderLine(line), !isSeparator(line), let price = trailingPrice(line), price.value > 0 {
                itemsStarted = true
            }
            return false
        }
        return lines[..<(end ?? lines.endIndex)]
    }

    private static let endWords = ["小計", "合計", "お買上", "御買上", "ご請求", "TOTAL", "お預", "預り", "お釣"]

    /// End words that can also appear in a header above the items (伝票番号, 会員番号).
    private static let endWordsAfterItems = [
        "対象", "内消費税", "支払", "現金", "電子マネー",
        "取引日", "伝票番号", "会員番号", "会社名", "承認番号", "お客様控", "売上票",
    ]

    /// A card slip's AID line, not inside a word (`MAID`).
    private static let cardSlipCode = try! NSRegularExpression(pattern: #"(?<![A-Z])AID(?![A-Z])"#)

    // MARK: - Separators

    /// Characters printed in a row as a separator, and what OCR makes of `====` (`ニーニニ`).
    private static let separatorCharacters = Set("=-_*~.・ー―‐─━−ニ二〜")

    /// A line of one repeated separator character (`==========`, `-----`, `ニーニニニ`), maybe with
    /// a price OCR attached to it. Never an item.
    static func isSeparator(_ line: String) -> Bool {
        var text = line
        if let price = trailingPrice(line) { text.removeSubrange(price.range) }
        let marks = text.filter { !$0.isWhitespace }
        return marks.count >= 4 && marks.allSatisfy(separatorCharacters.contains)
    }

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

    private static let discountWords = ["値引", "割引", "クーポン", "ネビキ", "半額", "%引", "円引"]
    /// OFF as a word, not inside COFFEE.
    private static let off = try! NSRegularExpression(pattern: #"(?<![A-Z])OFF(?![A-Z])"#, options: .caseInsensitive)

    static func isDiscount(_ line: String) -> Bool {
        discountWords.contains(where: line.contains)
            || off.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    /// `1点※ ¥270`, `2点 ¥396`: a count and the line's price, no name.
    private static let countLine = try! NSRegularExpression(pattern: #"^\s*\d+\s*点\s*[※★軽]?\s*¥?\s*\d"#)

    static func isCountLine(_ line: String) -> Bool {
        countLine.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    /// 7-Eleven's reduced-rate `*` right before the price (`手巻おにぎり *130`). Only on item
    /// lines: in a quantity line (`2*158`) the `*` is a multiplication sign.
    private static let starBeforePrice = try! NSRegularExpression(
        pattern: #"(?:^|\s)\*\s*¥?\s*(?:\d{1,3}(?:,\d{3})+|\d+)\s*[^\d\s]?\s*$"#
    )

    static func hasStarBeforePrice(_ line: String) -> Bool {
        starBeforePrice.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
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
    /// optionally followed by a rate mark (`198 ※`, `198軽`), a tax mark (`490込`, `50非`, `外`,
    /// `内`, `▽`), a `*`, or after a ¥ price a single letter tax or category mark (`¥199C`, `¥349 E`).
    ///
    /// Digits right after `:` `/` `-` `.` belong to a time, date or code, not a price, and so do
    /// digits without ¥ or 円 right after a letter (`津南60`, B-15).
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
        // A bare number glued to a name is part of it (`天然水新潟県津南60`), not a price.
        if !hasYen, match.range(at: 1).length == 0, digitsRange.lowerBound > line.startIndex,
           let before = line[..<digitsRange.lowerBound].last, before.isLetter { return nil }
        // A letter after a bare number is a unit or code (`350g`, `2P`), not a mark.
        if match.range(at: 5).length > 0, match.range(at: 2).length == 0 { return nil }
        let negative = match.range(at: 1).length > 0
        return Price(value: negative ? -value : value, range: whole)
    }

    /// Groups: 1 sign, 2 ¥, 3 digits, 4 円, 5 letter mark.
    private static let pricePattern = try! NSRegularExpression(
        pattern: #"(?<![\d:/\-.,])\s*([-▲△]\s*)?(¥\s*)?(?<![:/.\d,])(\d{1,3}(?:,\d{3})+|\d+)\s*(円)?\s*(?:[※★軽*込非▽]|外|内|(?<=\d|\d\s)([A-Za-z]))?\s*$"#
    )

    // MARK: - Names

    /// The line without its price and rate marks, or nil when nothing is left.
    static func cleanName(_ line: String, removing priceRange: Range<String.Index>?) -> String? {
        var name = line
        let markedBeforePrice = keiBeforePrice.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        if let priceRange {
            name.removeSubrange(priceRange)
            // 7-Eleven's `*` before the price.
            while let last = name.last, last == "*" || last == " " { name.removeLast() }
        }
        if markedBeforePrice, name.hasSuffix("軽") { name.removeLast() }
        for mark in ["※", "★", "▽"] { name = name.replacingOccurrences(of: mark, with: "") }
        name = name.trimmingCharacters(in: .whitespaces)
        while let first = name.first, "◎●○◆☆".contains(first) { name.removeFirst() }
        let range = NSRange(name.startIndex..., in: name)
        name = kei.stringByReplacingMatches(in: name, range: range, withTemplate: "")
        name = name.trimmingCharacters(in: .whitespaces)
        let codeRange = NSRange(name.startIndex..., in: name)
        name = departmentCode.stringByReplacingMatches(in: name, range: codeRange, withTemplate: "")
        return name.isEmpty ? nil : name
    }

    /// A 2–3 digit department code before the name (`01 テンネンスイ`). One digit or digits joined
    /// to the name (`7UP`, `3個入り`) are part of the name.
    private static let departmentCode = try! NSRegularExpression(pattern: #"^\d{2,3}\s+(?=\S)"#)

    private static let kei = try! NSRegularExpression(pattern: #"(?:^|\s)軽(?=$|\s)"#)

    // MARK: - Quantity lines

    /// `2コ × 198`, `2個 x 158 ¥316`, `3点 × @98 ¥294`, `@120 x 2`.
    struct Quantity {
        var count: Int
        var unitYen: Int
        /// The printed line total, or count × unit when none is printed.
        var lineTotal: Int
        /// An item name printed before the quantity on the same row, if any.
        var name: String?

        init?(_ line: String) {
            let range = NSRange(line.startIndex..., in: line)
            var count: Int?
            var unit: Int?
            var start = 0
            var end = 0
            // `@` marks the unit price, so read `@118× 2点` unit first: count first would take
            // 118 as the count.
            if let m = Quantity.unitFirst.firstMatch(in: line, range: range) {
                unit = Range(m.range(at: 1), in: line).flatMap { Int(line[$0].filter(\.isNumber)) }
                count = Range(m.range(at: 2), in: line).flatMap { Int(line[$0]) }
                (start, end) = (m.range.lowerBound, m.range.upperBound)
            } else if let m = Quantity.countFirst.firstMatch(in: line, range: range) {
                count = Range(m.range(at: 1), in: line).flatMap { Int(line[$0]) }
                unit = Range(m.range(at: 2), in: line).flatMap { Int(line[$0].filter(\.isNumber)) }
                (start, end) = (m.range.lowerBound, m.range.upperBound)
            }
            guard let count, let unit, count > 0, count < 1_000, unit > 0 else { return nil }
            self.count = count
            unitYen = unit
            // A total printed after the quantity: "3点 × @98 ¥294". When it disagrees with
            // count × unit, the printed total wins: the item-sum check then catches a misread.
            let rest = String(line[String.Index(utf16Offset: end, in: line)...])
            lineTotal = ItemParser.trailingPrice(rest)?.value ?? count * unit
            // A name before the quantity (`天然水新潟県津南60 @118× 2点`), not just brackets or marks.
            let before = String(line[..<String.Index(utf16Offset: start, in: line)])
                .trimmingCharacters(in: CharacterSet(charactersIn: " ([（"))
            if let cleaned = ItemParser.cleanName(before, removing: nil),
               cleaned.unicodeScalars.filter(CharacterSet.letters.contains).count >= 2 {
                name = cleaned
            }
        }

        private static let countFirst = try! NSRegularExpression(
            pattern: #"(\d+)\s*(?:コ|個|点|本|袋|枚|P|ケ)?\s*[x×*✕✖х]\s*(?:@|単)?\s*¥?\s*(\d{1,3}(?:,\d{3})+|\d+)"#,
            options: .caseInsensitive
        )
        private static let unitFirst = try! NSRegularExpression(
            pattern: #"@\s*¥?\s*(\d{1,3}(?:,\d{3})+|\d+)\s*[x×*✕✖х]\s*(\d+)"#,
            options: .caseInsensitive
        )
    }
}
