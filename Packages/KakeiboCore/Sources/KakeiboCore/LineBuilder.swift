import Foundation

/// Rebuilds receipt rows from OCR observations.
///
/// Vision returns an item name and its price as separate observations (often all names first,
/// then all prices). `LineBuilder` puts observations whose vertical centers line up into one
/// line, left to right, joined with a space, and orders lines top to bottom.
///
/// Slight skew is tolerated: the page's slope is estimated from observations that sit side by
/// side, and vertical centers are levelled with it before grouping. Rows may drift by half a
/// line height or more across the width.
public enum LineBuilder {
    public struct Line: Sendable, Equatable {
        /// The observations' text, left to right, joined with a space.
        public var text: String
        /// The observations in this line, left to right.
        public var observations: [TextObservation]
        /// The lowest OCR confidence in the line.
        public var confidence: Double { observations.map(\.confidence).min() ?? 0 }
    }

    /// Observations in one line must have levelled centers within this fraction of the line height.
    static let sameLineTolerance = 0.5

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

        let slope = estimateSlope(items)
        // Level each center: where it would be if the page were straight, measured at x = 0.
        let levelled = items.map { (observation: $0, y: $0.boundingBox.midY - slope * $0.boundingBox.midX) }
            .sorted { $0.y < $1.y }

        var groups: [[(observation: TextObservation, y: Double)]] = []
        for item in levelled {
            if var last = groups.last {
                let lineY = last.map(\.y).reduce(0, +) / Double(last.count)
                let height = max(item.observation.boundingBox.height, median(last.map(\.observation.boundingBox.height)))
                if abs(item.y - lineY) <= sameLineTolerance * height {
                    last.append(item)
                    groups[groups.count - 1] = last
                    continue
                }
            }
            groups.append([item])
        }

        return groups.map { group in
            let ordered = group.map(\.observation).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            return Line(text: ordered.map(\.text).joined(separator: " "), observations: ordered)
        }
    }

    // MARK: - Skew

    /// The page's slope (dy/dx in normalized units), from observations that sit side by side
    /// on what looks like the same row. Zero when there are no such pairs.
    static func estimateSlope(_ items: [TextObservation]) -> Double {
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

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
