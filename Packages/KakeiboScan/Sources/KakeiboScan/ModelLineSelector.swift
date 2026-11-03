import Foundation

/// Chooses which receipt lines to send to the on-device model, whose context window is small.
///
/// Short receipts are sent whole. Long ones send the header (store and date) and the lines
/// around the totals, widening the window around the totals until the budget is used.
public enum ModelLineSelector {
    /// Character budget for receipt lines in the prompt. Japanese text is roughly one token
    /// per character, and the instructions, the parser draft and the answer need room too.
    public static let characterBudget = 1_500

    /// Lines kept from the top for the store name and date.
    static let headerLineCount = 5

    static let totalWords = ["合計", "お買上", "御買上", "ご請求", "小計", "お預", "預り", "お釣", "釣銭", "TOTAL"]

    public static func select(_ lines: [String], budget: Int = characterBudget) -> [String] {
        func cost(_ indices: some Sequence<Int>) -> Int { indices.reduce(0) { $0 + lines[$1].count + 1 } }
        guard cost(lines.indices) > budget else { return lines }

        var chosen = Set(lines.indices.prefix(headerLineCount))
        let anchors = lines.indices.filter { i in totalWords.contains { lines[i].uppercased().contains($0) } }
        guard let first = anchors.first, let last = anchors.last else {
            // No totals found: send as much of the top as fits.
            return takeWhileFits(Array(lines.indices), lines: lines, budget: budget).map { lines[$0] }
        }

        // The totals block itself, then one more line above and below at a time.
        var low = first
        var high = last
        chosen.formUnion(low...high)
        while true {
            var grew = false
            if low > 0, cost(chosen.union([low - 1])) <= budget { low -= 1; chosen.insert(low); grew = true }
            if high < lines.count - 1, cost(chosen.union([high + 1])) <= budget { high += 1; chosen.insert(high); grew = true }
            if !grew { break }
        }
        // If even the header and totals block are over budget, trim from the top of the block.
        let ordered = chosen.sorted()
        return (cost(ordered) <= budget ? ordered : takeWhileFits(ordered.reversed(), lines: lines, budget: budget).sorted())
            .map { lines[$0] }
    }

    private static func takeWhileFits(_ indices: [Int], lines: [String], budget: Int) -> [Int] {
        var used = 0
        var taken: [Int] = []
        for i in indices {
            used += lines[i].count + 1
            guard used <= budget else { break }
            taken.append(i)
        }
        return taken
    }
}
