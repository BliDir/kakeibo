import Foundation

/// Cleans raw OCR lines before any field is parsed.
///
/// Rules, applied to each line in this order:
/// 1. NFKC: full-width digits, letters and symbols become half-width
///    (`１２３` → `123`, `ＴＯＴＡＬ` → `TOTAL`, half-width katakana → full-width).
/// 2. `\` and `￥` become `¥` (OCR often reads ¥ as a backslash).
/// 3. Whitespace runs collapse to one space; leading and trailing spaces go.
/// 4. Spaces inside numbers go: `1, 000` → `1,000`, `¥ 500` → `¥500`.
///    Only thousands commas join, so `1,000, 2` keeps its space.
/// 5. The letter `O`/`o` between digits becomes `0`: `1O0` → `100`, `1,O00` → `1,000`.
/// 6. Spaces between Japanese characters go: `合 計` → `合計`.
///
/// Line order is kept and lines that end up empty are dropped.
public enum TextNormalizer {
    /// Normalizes OCR lines, keeping order and dropping empty lines.
    public static func normalize(lines: [String]) -> [String] {
        lines.map(normalizeLine).filter { !$0.isEmpty }
    }

    /// Normalizes OCR text with one receipt row per line.
    public static func normalize(text: String) -> [String] {
        normalize(lines: text.components(separatedBy: .newlines))
    }

    /// Normalizes one line. Returns an empty string for a blank line.
    public static func normalizeLine(_ line: String) -> String {
        // NFKC, then NFC: Foundation's NFKC leaves half-width ﾌﾞ as フ + U+3099 instead of ブ.
        // Swift's == hides the difference, but regular expressions do not.
        var s = line.precomposedStringWithCompatibilityMapping.precomposedStringWithCanonicalMapping
        s = s.replacingOccurrences(of: "\\", with: "¥")
            .replacingOccurrences(of: "￥", with: "¥")
        s = replace(whitespaceRun, in: s, with: " ")
            .trimmingCharacters(in: .whitespaces)
        s = replace(spaceAroundNumberSeparator, in: s, with: "$1")
        s = replace(spaceAfterYen, in: s, with: "¥")
        s = replaceLetterOBetweenDigits(in: s)
        s = replace(spaceBetweenJapanese, in: s, with: "")
        return s
    }

    // MARK: - Patterns

    /// Hiragana, katakana (including ー and ・), CJK ideographs, and 々 〆 〇.
    private static let japanese = #"[\p{Hiragana}\p{Katakana}\p{Han}ー・々〆〇]"#

    private static let whitespaceRun = regex(#"\s+"#)
    /// Only a thousands comma (exactly three digits follow), so `1,000, 2` is not merged.
    /// `O`/`o` count as digits here because the letter-O rule runs afterwards (`1, O76`).
    private static let spaceAroundNumberSeparator = regex(#"(?<=\d) *(,) *(?=[\dOo]{3}(?![\dOo]))"#)
    private static let spaceAfterYen = regex(#"¥ +(?=\d)"#)
    private static let spaceBetweenJapanese = regex("(?<=\(japanese)) +(?=\(japanese))")

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are constants; a failure here is a programming error caught by tests.
        try! NSRegularExpression(pattern: pattern)
    }

    private static func replace(_ regex: NSRegularExpression, in s: String, with template: String) -> String {
        regex.stringByReplacingMatches(
            in: s,
            range: NSRange(s.startIndex..., in: s),
            withTemplate: template
        )
    }

    /// Turns each run of `O`/`o` into `0`s when it sits between digits.
    /// A single comma next to the run still counts as part of the number (`1,O00`, `1O,000`).
    private static func replaceLetterOBetweenDigits(in s: String) -> String {
        var chars = Array(s)
        var i = 0
        while i < chars.count {
            guard chars[i] == "O" || chars[i] == "o" else {
                i += 1
                continue
            }
            var end = i
            while end < chars.count, chars[end] == "O" || chars[end] == "o" {
                end += 1
            }
            if isDigit(before: i, in: chars), isDigit(after: end, in: chars) {
                for j in i..<end { chars[j] = "0" }
            }
            i = end
        }
        return String(chars)
    }

    private static func isDigit(before index: Int, in chars: [Character]) -> Bool {
        var k = index - 1
        if k >= 0, chars[k] == "," { k -= 1 }
        return k >= 0 && chars[k].isASCIIDigit
    }

    private static func isDigit(after index: Int, in chars: [Character]) -> Bool {
        var k = index
        if k < chars.count, chars[k] == "," { k += 1 }
        return k < chars.count && chars[k].isASCIIDigit
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
