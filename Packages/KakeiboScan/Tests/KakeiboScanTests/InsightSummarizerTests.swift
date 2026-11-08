import Foundation
import KakeiboCore
import Testing
@testable import KakeiboScan

/// A wording model with a fixed answer, optionally slow or failing, that records requests.
private final class FakeSentenceModel: InsightSentenceModel, @unchecked Sendable {
    let answer: String?
    let delay: Duration
    let languages: Set<AppLanguage>
    private let lock = NSLock()
    private var _requests: [InsightSentenceRequest] = []
    var requests: [InsightSentenceRequest] { lock.withLock { _requests } }

    init(_ answer: String?, delay: Duration = .zero, languages: Set<AppLanguage> = [.ja, .en]) {
        self.answer = answer
        self.delay = delay
        self.languages = languages
    }

    struct Failure: Error {}

    func supports(_ language: AppLanguage) -> Bool { languages.contains(language) }

    func sentence(for request: InsightSentenceRequest) async throws -> String {
        lock.withLock { _requests.append(request) }
        if delay > .zero { try await Task.sleep(for: delay) }
        guard let answer else { throw Failure() }
        return answer
    }
}

@MainActor
@Suite struct InsightSummarizerTests {
    static func facts(_ language: AppLanguage = .en, overYen: Int = 12_400) -> InsightSummaryFacts {
        InsightSummaryFacts(
            language: language, situation: .overBudget, budgetYen: 40_000, spentYen: 40_000 + overYen, overYen: overYen,
            drivers: [.init(kind: .categoryIncrease, name: ExpenseCategory.dining.displayName(for: language), yen: 8_400),
                      .init(kind: .largeOneOff, name: "ニトリ", yen: 20_000)])
    }

    static let good = "You're ¥12,400 over, mostly one purchase at ニトリ (¥20,000) and dining out ¥8,400 above usual."
    static let goodJa = "ニトリでの20,000円の買い物と外食の8,400円増で、予算を12,400円超えています。"

    @Test func acceptedSentenceIsReturned() async {
        let model = FakeSentenceModel(Self.good)
        #expect(await InsightSummarizer(model: model).sentence(for: Self.facts()) == Self.good)
    }

    @Test func wrongNumberFallsBackToTheTemplate() async {
        let model = FakeSentenceModel("You're ¥12,500 over, mostly dining out ¥8,400 above usual.")
        #expect(await InsightSummarizer(model: model).sentence(for: Self.facts()) == nil)
    }

    @Test func extraNumberFallsBackToTheTemplate() async {
        let model = FakeSentenceModel("You're ¥12,400 over after 3 dinners out, ¥8,400 above usual.")
        #expect(await InsightSummarizer(model: model).sentence(for: Self.facts()) == nil)
    }

    @Test func tooLongFallsBackToTheTemplate() async {
        let model = FakeSentenceModel(Self.good.dropLast() + String(repeating: " and so on", count: 10) + ".")
        #expect(await InsightSummarizer(model: model).sentence(for: Self.facts()) == nil)
    }

    @Test func noModelMeansTemplate() async {
        #expect(await InsightSummarizers.templateOnly().sentence(for: Self.facts()) == nil)
    }

    @Test func modelErrorMeansTemplate() async {
        #expect(await InsightSummarizer(model: FakeSentenceModel(nil)).sentence(for: Self.facts()) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func slowModelMeansTemplate() async {
        let model = FakeSentenceModel(Self.good, delay: .seconds(30))
        let summarizer = InsightSummarizer(model: model, timeLimit: .milliseconds(100))
        let start = ContinuousClock.now
        #expect(await summarizer.sentence(for: Self.facts()) == nil)
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func defaultTimeLimitIsShort() {
        #expect(InsightSummarizer.defaultTimeLimit <= .seconds(10))
    }

    // MARK: Language

    @Test func asksInTheUILanguage() async throws {
        let model = FakeSentenceModel(Self.goodJa)
        #expect(await InsightSummarizer(model: model).sentence(for: Self.facts(.ja)) == Self.goodJa)
        let request = try #require(model.requests.first)
        #expect(request.facts.language == .ja)
        #expect(request.instructions.contains("Japanese"))
        #expect(request.prompt.contains("8,400円"))
        #expect(request.prompt.contains(ExpenseCategory.dining.displayName(for: .ja)))

        let en = FakeSentenceModel(Self.good)
        _ = await InsightSummarizer(model: en).sentence(for: Self.facts(.en))
        let enRequest = try #require(en.requests.first)
        #expect(enRequest.instructions.contains("English"))
        #expect(enRequest.prompt.contains("¥8,400"))
    }

    @Test func answerInTheOtherLanguageFallsBack() async {
        #expect(await InsightSummarizer(model: FakeSentenceModel(Self.goodJa)).sentence(for: Self.facts(.en)) == nil)
        #expect(await InsightSummarizer(model: FakeSentenceModel(Self.good)).sentence(for: Self.facts(.ja)) == nil)
    }

    @Test func unsupportedLanguageIsNotAsked() async {
        let model = FakeSentenceModel(Self.goodJa, languages: [.en])
        #expect(await InsightSummarizer(model: model).sentence(for: Self.facts(.ja)) == nil)
        #expect(model.requests.isEmpty)
    }

    // MARK: Prompt

    @Test func promptHoldsOnlyTheFacts() {
        let prompt = InsightPrompt.prompt(for: Self.facts())
        #expect(prompt == """
        Situation: this month is over budget.
        Budget: ¥40,000
        Spent: ¥52,400
        Over budget by: ¥12,400
        Main causes, largest first:
        - Dining out: ¥8,400 above usual
        - one purchase at ニトリ: ¥20,000
        """)
        #expect(InsightPrompt.instructions(for: .en).contains("never judge"))
    }

    // MARK: Cache

    @Test func sameFactsAreAnsweredFromMemory() async {
        let model = FakeSentenceModel(Self.good)
        let summarizer = InsightSummarizer(model: model)
        _ = await summarizer.sentence(for: Self.facts())
        #expect(await summarizer.sentence(for: Self.facts()) == Self.good)
        #expect(model.requests.count == 1)
        #expect(summarizer.cachedSentence(for: Self.facts()) == .some(Self.good))
    }

    @Test func rejectedAnswersAreRememberedToo() async {
        let model = FakeSentenceModel("Way over.")
        let summarizer = InsightSummarizer(model: model)
        _ = await summarizer.sentence(for: Self.facts())
        #expect(summarizer.cachedSentence(for: Self.facts()) == .some(nil))
        #expect(await summarizer.sentence(for: Self.facts()) == nil)
        #expect(model.requests.count == 1)
    }

    @Test func onlyTheCurrentStateIsKept() async {
        let model = FakeSentenceModel(Self.good)
        let summarizer = InsightSummarizer(model: model)
        _ = await summarizer.sentence(for: Self.facts())
        // A new expense changes the figures: ask again, and forget the old state.
        #expect(await summarizer.sentence(for: Self.facts(overYen: 13_000)) == nil) // ¥12,400 no longer matches
        #expect(model.requests.count == 2)
        #expect(summarizer.cachedSentence(for: Self.facts()) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledRunIsNotCached() async {
        let model = FakeSentenceModel(Self.good, delay: .seconds(30))
        let summarizer = InsightSummarizer(model: model)
        let task = Task { await summarizer.sentence(for: Self.facts()) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        #expect(await task.value == nil)
        #expect(summarizer.cachedSentence(for: Self.facts()) == nil)
    }

    @Test func automaticUsesTheModelOnlyWhereAvailable() {
        #expect((InsightSummarizers.automatic().model != nil) == FoundationModelsRefiner.isAvailable)
    }
}

/// The real on-device model, where Apple Intelligence is available. Its answer may be
/// rejected (then the app shows the template); this checks that a call completes and that
/// whatever it returns is either nil or passes the check.
@MainActor
@Suite(.enabled(if: FoundationModelsRefiner.isAvailable, "Apple Intelligence not available"))
struct LiveInsightModelTests {
    @Test(.timeLimit(.minutes(1)), arguments: [AppLanguage.en, .ja])
    func liveSentenceIsCheckedOrNil(language: AppLanguage) async {
        let facts = InsightSummarizerTests.facts(language)
        let summarizer = InsightSummarizer(model: FoundationModelsInsightModel(), timeLimit: .seconds(30))
        if let sentence = await summarizer.sentence(for: facts) {
            print("[live insight \(language)] \(sentence)")
            #expect(throws: Never.self) { try InsightSentenceCheck.validate(sentence, facts: facts).get() }
        } else {
            let raw = try? await FoundationModelsInsightModel().sentence(for: InsightPrompt.request(for: facts))
            print("[live insight \(language)] fell back to the template: \(raw ?? "no answer") → \(raw.map { "\(InsightSentenceCheck.validate($0, facts: facts))" } ?? "")")
        }
    }
}
