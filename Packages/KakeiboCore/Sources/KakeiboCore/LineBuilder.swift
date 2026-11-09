import Foundation

/// Rebuilds receipt rows from OCR observations.
///
/// Vision returns an item name and its price as separate observations (often all names first,
/// then all prices). `LineBuilder` puts observations whose vertical centers line up into one
/// line, left to right, joined with a space, and orders lines top to bottom.
///
/// 1. **Skew.** Centers are levelled with the page's slope first. The slope comes from the
///    observations' own baselines when Vision reported them (`TextObservation.slope`, weighted
///    to long text), otherwise from observations that sit side by side; either estimate is then
///    tuned so the price column lines up best with the rows (B-15).
/// 2. **Rows.** Everything except the right-hand price column is grouped top to bottom.
/// 3. **Prices.** Each price (`¥170軽`, `1,469`) joins the row whose levelled center is nearest,
///    one price per row, closest pairs first. A price with no row near it stays a line of its own.
///    Greedy top-to-bottom grouping put prices on the row above when a tilted photo of tightly
///    printed rows (FamilyMart) drifted by more than half a line (B-15).
public enum LineBuilder {
    public struct Line: Sendable, Equatable {
        /// The observations' text, left to right, joined with a space.
        public var text: String
        /// The observations in this line, left to right.
        public var observations: [TextObservation]
        /// The lowest OCR confidence in the line.
        public var confidence: Double { observations.map(\.confidence).min() ?? 0 }
    }

    /// Observations in one row must have levelled centers within this fraction of the line height.
    static let sameLineTolerance = 0.5

    /// A price joins a row whose levelled center is within this fraction of the line height.
    static let priceTolerance = 0.75

    /// Candidate side-by-side pairs for the skew estimate may differ vertically by up to this
    /// fraction of their height.
    static let skewPairTolerance = 0.75

    /// Lines of text, top to bottom.
    public static func lines(from observations: [TextObservation]) -> [String] {
        build(observations).map(\.text)
    }

    /// Lines with their observations, top to bottom.
    public static func build(_ observations: [TextObservation]) -> [Line] {
        let items = observations.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !items.isEmpty else { return [] }
        let marked = items.map { (observation: $0, isPrice: isPriceColumn($0)) }
        let rows = assemble(marked, slope: estimateSlope(marked)).rows
        return rows.map { row in
            let ordered = row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            return Line(text: ordered.map(\.text).joined(separator: " "), observations: ordered)
        }
    }

    // MARK: - Rows

    private struct Levelled {
        var observation: TextObservation
        var isPrice: Bool
        var y: Double
        /// The text's own height: on a tilted page the box of a long name is taller by
        /// slope × width, which would let it swallow the rows next to it.
        var height: Double
    }

    /// Rows top to bottom, and how far the prices sit from their rows' centers (in line heights,
    /// capped), which the slope search minimizes.
    private static func assemble(_ items: [Marked], slope: Double) -> (rows: [[TextObservation]], cost: Double) {
        // Level each center: where it would be if the page were straight, measured at x = 0.
        let levelled = items.map { item in
            let box = item.observation.boundingBox
            return Levelled(observation: item.observation, isPrice: item.isPrice, y: box.midY - slope * box.midX,
                            height: max(box.height - abs(slope) * box.width, 0.4 * box.height))
        }
        let prices = levelled.filter(\.isPrice)
        let others = levelled.filter { !$0.isPrice }.sorted { $0.y < $1.y }

        var groups: [[Levelled]] = []
        for item in others {
            if var last = groups.last {
                let height = max(item.height, median(last.map(\.height)))
                if abs(item.y - center(last)) <= sameLineTolerance * height {
                    last.append(item)
                    groups[groups.count - 1] = last
                    continue
                }
            }
            groups.append([item])
        }

        // Nearest row center, one price per row, closest pairs first.
        var pairs: [(price: Int, row: Int, distance: Double)] = []
        for (p, price) in prices.enumerated() {
            for (r, group) in groups.enumerated() {
                let height = max(price.height, median(group.map(\.height)))
                let distance = abs(price.y - center(group)) / height
                if distance <= priceTolerance { pairs.append((p, r, distance)) }
            }
        }
        pairs.sort { $0.distance != $1.distance ? $0.distance < $1.distance : $0.price < $1.price }
        var rowOfPrice: [Int: Int] = [:]
        var rowTaken = Set<Int>()
        var cost = 0.0
        for pair in pairs where rowOfPrice[pair.price] == nil && !rowTaken.contains(pair.row) {
            rowOfPrice[pair.price] = pair.row
            rowTaken.insert(pair.row)
            cost += pair.distance
        }
        // A second price on a row that already has one (`158 ¥316`) only when right on it.
        for pair in pairs where rowOfPrice[pair.price] == nil && pair.distance <= sameLineTolerance {
            rowOfPrice[pair.price] = pair.row
            cost += pair.distance
        }

        var rows = groups
        var loose: [Levelled] = []
        for (p, price) in prices.enumerated() {
            if let r = rowOfPrice[p] { rows[r].append(price) } else { loose.append(price); cost += priceTolerance }
        }
        // Prices with no row: lines of their own, grouped among themselves.
        var looseRows: [[Levelled]] = []
        for price in loose.sorted(by: { $0.y < $1.y }) {
            if var last = looseRows.last, abs(price.y - center(last)) <= sameLineTolerance * max(price.height, median(last.map(\.height))) {
                last.append(price)
                looseRows[looseRows.count - 1] = last
            } else {
                looseRows.append([price])
            }
        }
        // A row's place is its text's center (its price may sit a little off).
        func place(_ row: [Levelled]) -> Double { center(row.filter { !$0.isPrice }.nonEmpty ?? row) }
        let all = (rows + looseRows).filter { !$0.isEmpty }.sorted { place($0) < place($1) }
        return (all.map { $0.map(\.observation) }, cost)
    }

    private static func center(_ group: [Levelled]) -> Double {
        group.map(\.y).reduce(0, +) / Double(group.count)
    }

    /// A price in the right half of the page: digits with an optional sign, ¥, 円 and one mark
    /// (`¥170軽`, `1,469`, `-30`, `¥199C`), or a rate mark on its own (`軽`, `※`).
    static func isPriceColumn(_ observation: TextObservation) -> Bool {
        guard observation.boundingBox.midX > 0.5 else { return false }
        let text = TextNormalizer.normalizeLine(observation.text)
        return pricePattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static let pricePattern = try! NSRegularExpression(
        pattern: #"^(?:[-▲△]?¥?\d{1,3}(?:,\d{3})+|[-▲△]?¥?\d+)\s*円?\s*(?:[※★軽*込非▽外内]|[A-Za-z])?$|^[※★軽]$"#
    )

    // MARK: - Skew

    typealias Marked = (observation: TextObservation, isPrice: Bool)

    /// The page's slope (dy/dx in normalized units).
    static func estimateSlope(_ items: [TextObservation]) -> Double {
        estimateSlope(items.map { ($0, isPriceColumn($0)) })
    }

    private static func estimateSlope(_ items: [Marked]) -> Double {
        let observations = items.map(\.observation)
        let prior = baselineSlope(observations) ?? pairSlope(observations)
        return tuned(prior, items)
    }

    /// The median baseline slope Vision reported, counting long text more (its corners give a
    /// steadier angle than a short price). Nil when no observation has one.
    static func baselineSlope(_ items: [TextObservation]) -> Double? {
        let weighted = items.compactMap { item -> (slope: Double, weight: Double)? in
            guard let slope = item.slope, slope.isFinite, item.boundingBox.width >= 0.05 else { return nil }
            return (slope, item.boundingBox.width)
        }.sorted { $0.slope < $1.slope }
        guard !weighted.isEmpty else { return nil }
        let half = weighted.reduce(0) { $0 + $1.weight } / 2
        var running = 0.0
        for item in weighted {
            running += item.weight
            if running >= half { return item.slope }
        }
        return weighted.last?.slope
    }

    /// From observations that sit side by side on what looks like the same row. Zero when there
    /// are no such pairs.
    static func pairSlope(_ items: [TextObservation]) -> Double {
        var slopes: [Double] = []
        for a in items {
            // An observation to the right that could be on the same row. When several could
            // (tight line spacing), the one closest vertically is on this row.
            let candidates = items.filter { b in
                b.boundingBox.minX >= a.boundingBox.maxX - 0.01
                    && abs(b.boundingBox.midY - a.boundingBox.midY)
                        <= skewPairTolerance * max(a.boundingBox.height, b.boundingBox.height)
            }
            guard let b = candidates.min(by: { x, y in
                let gapX = abs(x.boundingBox.midY - a.boundingBox.midY)
                let gapY = abs(y.boundingBox.midY - a.boundingBox.midY)
                return gapX != gapY ? gapX < gapY : x.boundingBox.minX < y.boundingBox.minX
            }) else { continue }
            let dx = b.boundingBox.midX - a.boundingBox.midX
            guard dx > 0.05 else { continue }
            slopes.append((b.boundingBox.midY - a.boundingBox.midY) / dx)
        }
        return median(slopes)
    }

    /// The slope near `prior` at which the prices sit closest to their rows' centers. The window
    /// is under half a row across the page, so it cannot jump to the row above or below.
    private static func tuned(_ prior: Double, _ items: [Marked]) -> Double {
        let prices = items.filter(\.isPrice).count
        guard prices > 0, prices < items.count else { return prior }
        let heights = items.map(\.observation.boundingBox.height)
        let window = 0.3 * median(heights)   // over a page width of 1: under half a line
        let steps = 12
        var best = (slope: prior, cost: assemble(items, slope: prior).cost)
        for step in -steps...steps where step != 0 {
            let slope = prior + window * Double(step) / Double(steps)
            let cost = assemble(items, slope: slope).cost
            if cost < best.cost - 1e-9 { best = (slope, cost) }
        }
        return best.slope
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

private extension Array {
    var nonEmpty: Self? { isEmpty ? nil : self }
}
