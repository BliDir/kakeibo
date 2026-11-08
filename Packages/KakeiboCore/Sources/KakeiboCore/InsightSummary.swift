import Foundation

// MARK: - Optional model wording (v1.2, BI-06)
//
// Where Apple's on-device model is available, it may rephrase the insight card's driver summary
// as one friendly sentence. It gets only `InsightSummaryFacts`: figures and names from BI-02's
// output, never receipt text or photos. `InsightSentenceCheck` decides whether its answer can be
// shown; the template sentence is used otherwise. The model call itself is not in Core.

/// What the model may say: BI-02's figures for one month, in the UI language.
public struct InsightSummaryFacts: Sendable, Hashable {
    public enum Situation: String, Sendable, Hashable {
        case onPace, overBudget, closedMonthOverBudget
    }

    /// One driver, with the figures its sentence may quote.
    public struct Driver: Sendable, Hashable {
        public enum Kind: String, Sendable, Hashable {
            case categoryIncrease, largeOneOff, moreVisits, newSpending
        }

        public let kind: Kind
        /// A category in the UI language, or a store's saved name.
        public let name: String
        /// Above usual (category increase), the purchase (large one-off), the extra spend (more
        /// visits) or the new amount (new spending).
        public let yen: Int
        /// More visits only.
        public let visits: Int?
        public let usualVisits: Int?

        public init(kind: Kind, name: String, yen: Int, visits: Int? = nil, usualVisits: Int? = nil) {
            self.kind = kind
            self.name = name
            self.yen = yen
            self.visits = visits
            self.usualVisits = usualVisits
        }
    }

    public let language: AppLanguage
    public let situation: Situation
    public let budgetYen: Int
    public let spentYen: Int
    /// Over budget only: S − B.
    public let overYen: Int?
    /// On pace only, when BI-01 has a projection.
    public let projectedYen: Int?
    /// At most 3, largest impact first; never empty.
    public let drivers: [Driver]

    public init(language: AppLanguage, situation: Situation, budgetYen: Int, spentYen: Int,
                overYen: Int? = nil, projectedYen: Int? = nil, drivers: [Driver]) {
        self.language = language
        self.situation = situation
        self.budgetYen = budgetYen
        self.spentYen = spentYen
        self.overYen = overYen
        self.projectedYen = projectedYen
        self.drivers = drivers
    }

    /// The facts for a month's analysis, or nil when the card has no driver summary to reword
    /// (no insight, limited history, no drivers, or figures out of range).
    public init?(_ analysis: OverspendAnalysis, language: AppLanguage) {
        let summary = analysis.insight.summary
        guard !analysis.isLimitedHistory, !analysis.drivers.isEmpty,
              let budget = summary.budgetYen, let spent = summary.spentYen else { return nil }
        let situation: Situation
        switch analysis.insight.state {
        case .none: return nil
        case .onPaceToOverspend: situation = .onPace
        case .overBudget: situation = .overBudget
        case .closedMonthOverBudget: situation = .closedMonthOverBudget
        }
        let drivers = analysis.drivers.compactMap { Self.driver($0, language: language) }
        guard !drivers.isEmpty else { return nil }
        self.init(language: language, situation: situation, budgetYen: budget, spentYen: spent,
                  overYen: situation == .onPace ? nil : summary.overspentYen,
                  projectedYen: situation == .onPace ? analysis.insight.projectedYen : nil,
                  drivers: drivers)
    }

    private static func driver(_ driver: OverspendDriver, language: AppLanguage) -> Driver? {
        func name(_ target: InsightTarget) -> String {
            switch target {
            case .category(let category): category.displayName(for: language)
            case .store(let store): store.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        switch driver.suggestion {
        case .categoryIncrease(let category, let above, _):
            return Driver(kind: .categoryIncrease, name: category.displayName(for: language), yen: above)
        case .moreVisits(let target, let visits, let usual, _, _):
            return Driver(kind: .moreVisits, name: name(target), yen: driver.impactYen, visits: visits, usualVisits: usual)
        case .largeOneOff(let category, let store, _, let amount, _, _):
            let trimmed = store.trimmingCharacters(in: .whitespacesAndNewlines)
            return Driver(kind: .largeOneOff, name: trimmed.isEmpty ? category.displayName(for: language) : trimmed,
                          yen: amount)
        case .newSpending(let target, let amount):
            return Driver(kind: .newSpending, name: name(target), yen: amount)
        case .shareOfBudget:
            return nil
        }
    }

    /// Every number the sentence may contain. "One purchase" is allowed when a driver is a
    /// single large purchase.
    public var figures: Set<Int> {
        var figures: Set<Int> = [budgetYen, spentYen]
        if let overYen { figures.insert(overYen) }
        if let projectedYen { figures.insert(projectedYen) }
        for driver in drivers {
            figures.insert(driver.yen)
            if let visits = driver.visits { figures.insert(visits) }
            if let usual = driver.usualVisits { figures.insert(usual) }
            if driver.kind == .largeOneOff { figures.insert(1) }
        }
        return figures
    }

    /// Names the sentence may repeat as written (they can contain digits: "7-Eleven 3丁目店").
    public var names: [String] {
        drivers.map(\.name).filter { !$0.isEmpty }
    }
}

/// Decides whether a model's sentence can replace the template.
public enum InsightSentenceCheck {
    public enum Rejection: Error, Sendable, Equatable {
        case empty
        case notOneSentence
        case tooLong
        /// A number that is not one of the input figures (or a decimal, or badly grouped).
        case unknownNumber(String)
        /// A number written in words or kanji that is not an input figure, or a scale word
        /// (thousand, 万) that would hide one.
        case spelledNumber(String)
        case wrongLanguage
        /// Suggestions describe and quantify; they never judge.
        case judgement
        /// Suggestions quantify: the sentence must quote at least one input figure in digits.
        case noFigures
    }

    /// The longest sentence shown, in characters. The card's template sentences are well under.
    public static func maximumLength(for language: AppLanguage) -> Int {
        switch language {
        case .ja: 80
        case .en: 160
        }
    }

    /// The cleaned sentence when it can be shown, or why not.
    public static func validate(_ text: String, facts: InsightSummaryFacts) -> Result<String, Rejection> {
        var sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("\"", "\""), ("“", "”"), ("「", "」"), ("'", "'")]
        where sentence.count >= 2 && sentence.hasPrefix(open) && sentence.hasSuffix(close) {
            sentence = String(sentence.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !sentence.isEmpty else { return .failure(.empty) }
        guard !sentence.contains(where: \.isNewline) else { return .failure(.notOneSentence) }
        guard sentence.count <= maximumLength(for: facts.language) else { return .failure(.tooLong) }
        if let rejection = sentenceCount(sentence) { return .failure(rejection) }

        // Names are allowed as written, digits and all; check the rest.
        var rest = sentence
        for name in facts.names.sorted(by: { $0.count > $1.count }) {
            rest = rest.replacingOccurrences(of: name, with: " ")
        }
        if let rejection = checkNumbers(rest, figures: facts.figures) { return .failure(rejection) }
        if let rejection = checkSpelledNumbers(rest, figures: facts.figures) { return .failure(rejection) }
        guard rest.contains(where: { $0.isNumber && $0.isASCII || ("０"..."９").contains($0) }) else {
            return .failure(.noFigures)
        }
        guard isInLanguage(rest, facts.language) else { return .failure(.wrongLanguage) }
        if judges(rest) { return .failure(.judgement) }
        return .success(sentence)
    }

    /// One sentence: at most one sentence end, and only at the end.
    private static func sentenceCount(_ sentence: String) -> Rejection? {
        let ends: Set<Character> = ["。", "！", "？", "!", "?"]
        let body = sentence.dropLast()
        if body.contains(where: { ends.contains($0) }) { return .notOneSentence }
        // ". " followed by more text starts a second English sentence.
        if sentence.range(of: #"[.](\s+)\S"#, options: .regularExpression) != nil { return .notOneSentence }
        return nil
    }

    private static func checkNumbers(_ text: String, figures: Set<Int>) -> Rejection? {
        let ascii = String(text.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 0xFF10...0xFF19: Character(UnicodeScalar(scalar.value - 0xFF10 + 0x30)!) // ０-９
            case 0xFF0C: ","  // ，
            case 0xFF0E: "."  // ．
            default: Character(scalar)
            }
        })
        let regex = /[0-9][0-9,.]*/
        for match in ascii.matches(of: regex) {
            var token = String(match.output)
            while let last = token.last, last == "," || last == "." { token.removeLast() }
            guard token.wholeMatch(of: /[0-9]{1,3}(,[0-9]{3})*|[0-9]+/) != nil,
                  let value = Int(token.replacingOccurrences(of: ",", with: "")),
                  figures.contains(value) else { return .unknownNumber(token) }
        }
        return nil
    }

    private static let englishNumbers: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30,
        "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
        "first": 1, "second": 2, "third": 3, "single": 1,
    ]
    /// Words that scale or hide a number: never allowed.
    private static let englishScales: Set<String> = [
        "hundred", "hundreds", "thousand", "thousands", "million", "millions", "billion", "k",
        "dozen", "dozens", "half", "twice", "double", "triple", "quarter", "percent",
    ]
    private static let kanjiDigits: [Character: Int] = [
        "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
        "壱": 1, "弐": 2,
    ]
    private static let kanjiScales: Set<Character> = ["〇", "零", "十", "百", "千", "万", "億", "兆", "拾", "萬"]

    private static func checkSpelledNumbers(_ text: String, figures: Set<Int>) -> Rejection? {
        for word in text.lowercased().split(whereSeparator: { !$0.isLetter }) {
            let word = String(word)
            if englishScales.contains(word) { return .spelledNumber(word) }
            if let value = englishNumbers[word], !figures.contains(value) { return .spelledNumber(word) }
        }
        for character in text {
            if kanjiScales.contains(character) { return .spelledNumber(String(character)) }
            if let value = kanjiDigits[character], !figures.contains(value) { return .spelledNumber(String(character)) }
        }
        return nil
    }

    private static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        (0x3040...0x30FF).contains(scalar.value) || (0xFF66...0xFF9D).contains(scalar.value)
    }

    private static func isJapanese(_ scalar: Unicode.Scalar) -> Bool {
        isKana(scalar) || (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
    }

    /// Japanese needs kana; English needs Latin letters and no Japanese outside the names.
    private static func isInLanguage(_ text: String, _ language: AppLanguage) -> Bool {
        let scalars = text.unicodeScalars
        switch language {
        case .ja:
            return scalars.contains(where: isKana)
        case .en:
            let latin = scalars.contains { ("a"..."z").contains($0) || ("A"..."Z").contains($0) }
            return latin && !scalars.contains(where: isJapanese)
        }
    }

    private static func judges(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.range(of: #"\b(wast(e|ed|es|ing|eful)|careless|reckless|irresponsible|foolish|bad habit)"#,
                       options: .regularExpression) != nil { return true }
        return ["無駄", "ムダ", "浪費", "むだ"].contains { text.contains($0) }
    }
}
