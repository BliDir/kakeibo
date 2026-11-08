import Foundation
import KakeiboCore

/// What the wording model is asked (v1.2, BI-06): the instructions, the prompt built from the
/// facts only, and the facts themselves (for test doubles).
public struct InsightSentenceRequest: Sendable {
    public let facts: InsightSummaryFacts
    public let instructions: String
    public let prompt: String
}

/// A model that writes one sentence for the insight card. Plain strings, so the summarizer's
/// rules are testable without Foundation Models.
public protocol InsightSentenceModel: Sendable {
    /// Whether the model can write in this language on this iPhone right now.
    func supports(_ language: AppLanguage) -> Bool
    func sentence(for request: InsightSentenceRequest) async throws -> String
}

/// Turns BI-02's figures into an optional model sentence for the insight card.
///
/// `sentence(for:)` returns nil whenever the template should be shown: no model (unsupported
/// iPhone, Apple Intelligence off, UI tests), a language the model does not support, a model
/// error, no answer within `timeLimit`, or an answer `InsightSentenceCheck` rejects. Callers show
/// the template at once and swap in the sentence only if one comes back.
///
/// The only thing kept is the last answer, in memory, for the facts it was made from (the
/// current state), so reloads of the same month do not ask again. Nothing is written to disk.
@MainActor
public final class InsightSummarizer {
    public let model: (any InsightSentenceModel)?
    public let timeLimit: Duration

    /// A sentence is short: the on-device model usually answers in a few seconds. After this,
    /// the template stays.
    public static let defaultTimeLimit: Duration = .seconds(10)

    private var cache: (facts: InsightSummaryFacts, sentence: String?)?

    public init(model: (any InsightSentenceModel)?, timeLimit: Duration = InsightSummarizer.defaultTimeLimit) {
        self.model = model
        self.timeLimit = timeLimit
    }

    /// The cached answer for exactly these facts, without asking the model.
    public func cachedSentence(for facts: InsightSummaryFacts) -> String?? {
        guard let cache, cache.facts == facts else { return nil }
        return .some(cache.sentence)
    }

    /// A checked sentence for the facts, or nil for the template.
    public func sentence(for facts: InsightSummaryFacts) async -> String? {
        if let cached = cachedSentence(for: facts) { return cached }
        guard let model, model.supports(facts.language) else { return nil }
        let request = InsightPrompt.request(for: facts)
        let answer = await ModelRefiner.withTimeLimit(timeLimit) { try await model.sentence(for: request) }
        // A cancelled run (the month or figures changed) is not an answer for these facts.
        guard !Task.isCancelled else { return nil }
        let sentence = answer.flatMap { try? InsightSentenceCheck.validate($0, facts: facts).get() }
        cache = (facts, sentence)
        return sentence
    }
}

/// The wording model's instructions and prompt. Everything in the prompt comes from
/// `InsightSummaryFacts`; nothing from receipts.
public enum InsightPrompt {
    public static func request(for facts: InsightSummaryFacts) -> InsightSentenceRequest {
        InsightSentenceRequest(facts: facts, instructions: instructions(for: facts.language), prompt: prompt(for: facts))
    }

    public static func instructions(for language: AppLanguage) -> String {
        let languageRule = switch language {
        case .ja: "Write in natural, polite Japanese (です/ます). Write amounts like 12,400円. Write exactly one sentence with a single 。 at the very end; join ideas with 、 instead of starting a new sentence."
        case .en: "Write in plain English. Write amounts like ¥12,400."
        }
        return """
        You write one short, friendly sentence for a household budget app. \
        Summarise why this month's spending is high, using only the facts given. \
        \(languageRule) \
        Copy every number exactly as given, with Arabic digits; never round, add, subtract or invent numbers, never call one figure a total of others, \
        and never write numbers as words. \
        Describe and quantify; never judge, blame or scold. \
        Answer with the sentence only: no quotes, no line breaks, at most \
        \(InsightSentenceCheck.maximumLength(for: language)) characters.
        """
    }

    public static func prompt(for facts: InsightSummaryFacts) -> String {
        let yen = { (amount: Int) in Yen.format(amount, for: facts.language) }
        var lines: [String] = []
        switch facts.situation {
        case .onPace: lines.append("Situation: this month is on pace to go over budget.")
        case .overBudget: lines.append("Situation: this month is over budget.")
        case .closedMonthOverBudget: lines.append("Situation: a past month that went over budget.")
        }
        lines.append("Budget: \(yen(facts.budgetYen))")
        lines.append("Spent: \(yen(facts.spentYen))")
        if let over = facts.overYen { lines.append("Over budget by: \(yen(over))") }
        if let projected = facts.projectedYen { lines.append("Projected month-end spend: \(yen(projected))") }
        lines.append("Main causes, largest first:")
        for driver in facts.drivers {
            let line = switch driver.kind {
            case .categoryIncrease: "\(driver.name): \(yen(driver.yen)) above usual"
            case .largeOneOff: "one purchase at \(driver.name): \(yen(driver.yen))"
            case .moreVisits: "\(driver.name): \(driver.visits ?? 0) visits vs \(driver.usualVisits ?? 0) usual, \(yen(driver.yen)) extra"
            case .newSpending: "new this month, \(driver.name): \(yen(driver.yen))"
            }
            lines.append("- " + line)
        }
        return lines.joined(separator: "\n")
    }
}

@MainActor
public enum InsightSummarizers {
    /// Apple's on-device model when it is available, otherwise no model (template only).
    public static func automatic() -> InsightSummarizer {
        InsightSummarizer(model: FoundationModelsRefiner.isAvailable ? FoundationModelsInsightModel() : nil)
    }

    /// Template only: unsupported iPhones, UI tests.
    public static func templateOnly() -> InsightSummarizer {
        InsightSummarizer(model: nil)
    }
}
