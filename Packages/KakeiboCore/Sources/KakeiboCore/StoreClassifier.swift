import Foundation

/// Names the store and suggests a category from normalized receipt lines.
///
/// 1. The chain dictionary (`Resources/chains.json`) is searched in every line.
///    A brand match sets the canonical store name, its English name and the category.
///    A generic match (タクシー, クリニック, ...) sets only the category.
/// 2. Without a brand match, the store name is the first of the top 6 lines with at least
///    2 letters, more letters than digits, and no header phrase or address.
/// 3. Without any match, the category is `other` with low confidence.
public enum StoreClassifier {
    public struct Result: Sendable, Equatable {
        public var storeName: String?
        public var storeNameEn: String?
        /// `high` for a brand match, `medium` for a name read from the header lines.
        public var storeConfidence: Confidence
        public var category: ExpenseCategory
        /// `high` for a brand match, `medium` for a generic match, `low` for `other`.
        public var categoryConfidence: Confidence
    }

    public static func classify(lines: [String]) -> Result {
        let brand = bestMatch(in: lines, generic: false)
        let generic = brand == nil ? bestMatch(in: lines, generic: true) : nil
        let readName = storeLine(in: lines)

        if let brand {
            return Result(
                storeName: brand.name ?? readName,
                storeNameEn: brand.nameEn,
                storeConfidence: .high,
                category: brand.category,
                categoryConfidence: .high
            )
        }
        return Result(
            storeName: readName,
            storeNameEn: nil,
            storeConfidence: readName == nil ? .low : .medium,
            category: generic?.category ?? .other,
            categoryConfidence: generic == nil ? .low : .medium
        )
    }

    // MARK: - Store line heuristic

    /// How many lines from the top may hold the store name.
    public static let headerLineCount = 6

    static let headerPhrases = [
        "領収書", "領収証", "レシート", "いらっしゃいませ", "ありがとう", "ようこそ", "毎度",
        "お客様控", "電話", "〒", "登録番号", "合計",
    ]
    /// Latin header words, matched as whole words so `TEL` does not reject `HOTEL`.
    private static let headerWordPattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z])(?:TEL|FAX|HTTPS?|WWW)(?![A-Za-z])"#, options: .caseInsensitive
    )

    /// Prefecture followed by a city, ward, town or village: an address line.
    private static let addressPattern = try! NSRegularExpression(pattern: #"[都道府県].*[市区町村郡]"#)

    static func storeLine(in lines: [String]) -> String? {
        lines.prefix(headerLineCount).first { line in
            let letters = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            let digits = line.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
            guard letters >= 2, letters > digits else { return false }
            guard !headerPhrases.contains(where: line.contains) else { return false }
            let range = NSRange(line.startIndex..., in: line)
            return headerWordPattern.firstMatch(in: line, range: range) == nil
                && addressPattern.firstMatch(in: line, range: range) == nil
        }
    }

    // MARK: - Dictionary

    struct Chain: Decodable, Sendable {
        var name: String?
        var nameEn: String?
        var category: ExpenseCategory
        var match: [String]
        var generic: Bool?

        var isGeneric: Bool { generic ?? false }
    }

    private struct ChainFile: Decodable {
        var version: Int
        var chains: [Chain]
    }

    /// Every chain in the dictionary.
    static let chains: [Chain] = {
        guard let url = Bundle.module.url(forResource: "chains", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ChainFile.self, from: data)
        else {
            // The file ships inside the package; tests fail loudly if it is missing or malformed.
            assertionFailure("chains.json missing or invalid")
            return []
        }
        return file.chains
    }()

    /// One pattern per match key, compiled once.
    private static let keys: [(pattern: NSRegularExpression, length: Int, chain: Chain)] = chains.flatMap { chain in
        chain.match.map { raw in
            let key = TextNormalizer.normalizeLine(raw).filter { !$0.isWhitespace }
            return (pattern(for: key, strict: !chain.isGeneric), key.count, chain)
        }
    }

    /// The match on the earliest line; on the same line, the longest key.
    private static func bestMatch(in lines: [String], generic: Bool) -> Chain? {
        for line in lines {
            let text = stripCompanyForms(line)
            let range = NSRange(text.startIndex..., in: text)
            let hits = keys.filter { $0.chain.isGeneric == generic && $0.pattern.firstMatch(in: text, range: range) != nil }
            if let best = hits.max(by: { $0.length < $1.length }) {
                return best.chain
            }
        }
        return nil
    }

    private static let companyForms = ["株式会社", "(株)", "有限会社", "(有)"]

    private static func stripCompanyForms(_ line: String) -> String {
        companyForms.reduce(line) { $0.replacingOccurrences(of: $1, with: " ") }
    }

    /// A case-insensitive pattern for a key that allows one space between any two characters
    /// (OCR spacing such as `BIC CAMERA` or `au PAY`).
    ///
    /// With `strict`, the key must not continue a word:
    /// - a kana key may not follow kana (イオン is not in ライオン),
    ///   and a kana key of 3 characters or fewer may not be followed by kana (ガスト is not in ガストロノミー),
    /// - a Latin key may not touch Latin letters on either side,
    /// - a kanji key of 1–2 characters may not follow kanji (西友 is not in 関西友).
    static func pattern(for key: String, strict: Bool) -> NSRegularExpression {
        let body = key.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: " ?")
        var before = ""
        var after = ""
        if strict, let first = key.first, let last = key.last {
            let kana = #"[\p{Hiragana}\p{Katakana}ー]"#
            if first.isKana { before = "(?<!\(kana))" }
            if first.isLatinLetter { before = "(?<![A-Za-z])" }
            if key.count <= 2, first.isKanji { before = #"(?<!\p{Han})"# }
            if last.isLatinLetter { after = "(?![A-Za-z])" }
            if last.isKana, key.count <= 3 { after = "(?!\(kana))" }
        }
        return try! NSRegularExpression(pattern: before + body + after, options: .caseInsensitive)
    }
}

private extension Character {
    var isKana: Bool {
        unicodeScalars.allSatisfy { (0x3041...0x30FF).contains($0.value) && $0.value != 0x30FB }
    }
    var isKanji: Bool {
        unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }
    var isLatinLetter: Bool { isASCII && isLetter }
}
