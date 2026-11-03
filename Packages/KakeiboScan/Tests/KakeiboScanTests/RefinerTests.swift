import Foundation
import KakeiboCore
import Testing
@testable import KakeiboScan

/// A model that returns a fixed answer, optionally after a delay, and records the prompt.
final class MockModel: ReceiptModel, @unchecked Sendable {
    let answer: ModelReceipt?
    let delay: Duration
    private let lock = NSLock()
    private var _prompts: [String] = []
    var prompts: [String] { lock.withLock { _prompts } }

    init(_ answer: ModelReceipt?, delay: Duration = .zero) {
        self.answer = answer
        self.delay = delay
    }

    struct Failure: Error {}

    func read(prompt: String) async throws -> ModelReceipt {
        lock.withLock { _prompts.append(prompt) }
        if delay > .zero { try await Task.sleep(for: delay) }
        guard let answer else { throw Failure() }
        return answer
    }
}

private let today = Date(timeIntervalSince1970: 1_793_674_800)

@Suite struct RefinementMergerTests {
    private func draft(total: Int?, totalConfidence: Confidence) -> ReceiptDraft {
        var d = ReceiptDraft(storeName: "マルエツ", dayKey: "2026-11-03", totalYen: total, payment: .credit, category: .groceries)
        d.confidences = [.storeName: .medium, .dayKey: .high, .payment: .high, .category: .high]
        if total != nil { d.confidences[.totalYen] = totalConfidence }
        return d
    }

    @Test func checkedParserTotalIsKeptAndStaysHigh() {
        let merged = RefinementMerger.merge(draft: draft(total: 754, totalConfidence: .high), model: ModelReceipt(totalYen: 1_000))
        #expect(merged.totalYen == 754)
        #expect(merged.confidence(for: .totalYen) == .high)
    }

    @Test func uncheckedDisagreementKeepsParserTotalButMarksLow() {
        let merged = RefinementMerger.merge(draft: draft(total: 754, totalConfidence: .medium), model: ModelReceipt(totalYen: 745))
        #expect(merged.totalYen == 754)
        #expect(merged.confidence(for: .totalYen) == .low)
    }

    @Test func uncheckedAgreementKeepsConfidence() {
        let merged = RefinementMerger.merge(draft: draft(total: 754, totalConfidence: .medium), model: ModelReceipt(totalYen: 754))
        #expect(merged.confidence(for: .totalYen) == .medium)
    }

    @Test func modelFillsMissingTotalAsLow() {
        let merged = RefinementMerger.merge(draft: draft(total: nil, totalConfidence: .low), model: ModelReceipt(totalYen: 980))
        #expect(merged.totalYen == 980)
        #expect(merged.confidence(for: .totalYen) == .low)
    }

    @Test(arguments: [0, -5, 50_000_000])
    func ignoresNonsenseTotals(total: Int) {
        let merged = RefinementMerger.merge(draft: draft(total: nil, totalConfidence: .low), model: ModelReceipt(totalYen: total))
        #expect(merged.totalYen == nil)
    }

    @Test func fillsOnlyMissingFields() {
        var d = ReceiptDraft(totalYen: 1_089, payment: .cash, category: .other,
                             confidences: [.totalYen: .high, .payment: .low, .category: .low])
        d.tax8Yen = 48
        d.confidences[.tax8Yen] = .high
        let model = ModelReceipt(storeName: "マルエツ 中野店", dayKey: "2026-10-28", totalYen: 1_089,
                                 tax10Yen: 39, tax8Yen: 50, payment: .credit)
        let merged = RefinementMerger.merge(draft: d, model: model)

        #expect(merged.storeName == "マルエツ 中野店")
        #expect(merged.confidence(for: .storeName) == .medium)
        #expect(merged.dayKey == "2026-10-28")
        #expect(merged.confidence(for: .dayKey) == .medium)
        #expect(merged.tax10Yen == 39)
        #expect(merged.tax8Yen == 48)                       // parser value kept
        #expect(merged.confidence(for: .tax8Yen) == .high)
        #expect(merged.payment == .credit)                  // parser only defaulted to cash
        #expect(merged.confidence(for: .payment) == .medium)
        // Model store name matched the chain dictionary.
        #expect(merged.category == .groceries)
        #expect(merged.confidence(for: .category) == .medium)
        #expect(merged.storeNameEn == "Maruetsu")
    }

    @Test func keepsParserFieldsTheModelDisagreesWith() {
        let d = draft(total: 754, totalConfidence: .high)
        let merged = RefinementMerger.merge(draft: d, model: ModelReceipt(storeName: "別の店", dayKey: "2026-01-01", payment: .cash))
        #expect(merged.storeName == "マルエツ")
        #expect(merged.dayKey == "2026-11-03")
        #expect(merged.payment == .credit)
    }

    @Test func ignoresBadModelDatesAndTaxes() {
        let d = ReceiptDraft(totalYen: 500, confidences: [.totalYen: .high])
        let merged = RefinementMerger.merge(draft: d, model: ModelReceipt(dayKey: "2026-02-30", tax10Yen: 500, tax8Yen: -1))
        #expect(merged.dayKey == nil)
        #expect(merged.tax10Yen == nil)
        #expect(merged.tax8Yen == nil)
    }

    @Test func modelItemsUsedWhenParserHasNone() {
        let items = [LineItemDraft(name: "牛乳", nameEn: "Milk", priceYen: 198, isReducedRate: true),
                     LineItemDraft(name: "値引", nameEn: "Discount", priceYen: -20),
                     LineItemDraft(name: " ", priceYen: 0)]
        let merged = RefinementMerger.merge(draft: draft(total: 178, totalConfidence: .high), model: ModelReceipt(items: items))
        #expect(merged.items.map(\.name) == ["牛乳", "値引"])
        #expect(merged.items[0].nameEn == "Milk")
        #expect(merged.items[0].isReducedRate)
        #expect(merged.confidence(for: .items) == .medium)
    }

    @Test func parserItemsKeptAndEnglishNamesAdded() {
        var d = draft(total: 356, totalConfidence: .high)
        d.items = [LineItemDraft(name: "牛乳", priceYen: 198), LineItemDraft(name: "食パン", priceYen: 158)]
        let model = ModelReceipt(items: [LineItemDraft(name: "牛乳", nameEn: "Milk", priceYen: 198),
                                         LineItemDraft(name: "食パン", nameEn: "Bread", priceYen: 160),
                                         LineItemDraft(name: "卵", nameEn: "Eggs", priceYen: 248)])
        let merged = RefinementMerger.merge(draft: d, model: model)
        #expect(merged.items.map(\.name) == ["牛乳", "食パン"])
        #expect(merged.items.map(\.nameEn) == ["Milk", nil])   // price differs, so no match
    }

    @Test func emptyModelAnswerChangesNothing() {
        let d = draft(total: 754, totalConfidence: .medium)
        #expect(RefinementMerger.merge(draft: d, model: ModelReceipt()) == d)
    }
}

@Suite struct ModelRefinerTests {
    static let lines = ["マルエツ 中野店", "2026/10/28", "牛乳 ※ 198", "合計 ¥198"]

    @Test func mergesModelAnswer() async {
        let model = MockModel(ModelReceipt(items: [LineItemDraft(name: "牛乳", nameEn: "Milk", priceYen: 198, isReducedRate: true)]))
        let draft = ReceiptParser.parse(lines: Self.lines, today: today)
        let refined = await ModelRefiner(model: model).refine(lines: Self.lines, draft: draft)
        #expect(refined.items.first?.nameEn == "Milk")
        #expect(refined.totalYen == 198)
    }

    @Test func promptHasLinesAndParserFindings() async {
        let model = MockModel(ModelReceipt())
        let draft = ReceiptParser.parse(lines: Self.lines, today: today)
        _ = await ModelRefiner(model: model).refine(lines: Self.lines, draft: draft)
        let prompt = try! #require(model.prompts.first)
        #expect(prompt.contains("合計 ¥198"))
        #expect(prompt.contains("- total: 198"))
        #expect(prompt.contains("- date: 2026-10-28"))
        #expect(prompt.contains("- payment: not found"))   // only defaulted to cash
    }

    @Test func timeLimitReturnsDraftUnchanged() async {
        let model = MockModel(ModelReceipt(totalYen: 1, items: [LineItemDraft(name: "x", priceYen: 1)]), delay: .seconds(5))
        let draft = ReceiptParser.parse(lines: Self.lines, today: today)
        let start = ContinuousClock.now
        let refined = await ModelRefiner(model: model, timeLimit: .milliseconds(200)).refine(lines: Self.lines, draft: draft)
        #expect(refined == draft)
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func modelErrorReturnsDraftUnchanged() async {
        let draft = ReceiptParser.parse(lines: Self.lines, today: today)
        #expect(await ModelRefiner(model: MockModel(nil)).refine(lines: Self.lines, draft: draft) == draft)
    }

    @Test func defaultTimeLimitIsTenSeconds() {
        #expect(ModelRefiner.defaultTimeLimit == .seconds(10))
    }

    @Test func noopReturnsDraft() async {
        let draft = ReceiptParser.parse(lines: Self.lines, today: today)
        #expect(await NoopRefiner().refine(lines: Self.lines, draft: draft) == draft)
    }

    @Test func automaticSelection() {
        #expect(ReceiptRefiners.select(isModelAvailable: false) is NoopRefiner)
        #expect(ReceiptRefiners.select(isModelAvailable: true) is FoundationModelsRefiner)
        let automatic = ReceiptRefiners.automatic()
        #expect((automatic is FoundationModelsRefiner) == FoundationModelsRefiner.isAvailable)
    }
}

@Suite struct ModelLineSelectorTests {
    @Test func shortReceiptSentWhole() {
        let lines = ["店", "2026/11/03", "牛乳 198", "合計 198"]
        #expect(ModelLineSelector.select(lines) == lines)
    }

    @Test func longReceiptSendsHeaderAndLinesAroundTotals() {
        var lines = ["サンプルマート", "東京都中野区", "2026/11/03 18:42", "登録番号 T1234567890123", "レジ1"]
        lines += (1...300).map { "商品\($0) ※ ¥\($0 * 10)" }
        lines += ["小計 ¥451,500", "合計 ¥451,500", "お預り ¥460,000", "お釣り ¥8,500"]
        lines += (1...50).map { "ポイント案内 \($0)" }

        let selected = ModelLineSelector.select(lines, budget: 400)
        #expect(selected.reduce(0) { $0 + $1.count + 1 } <= 400)
        #expect(Array(selected.prefix(5)) == Array(lines.prefix(5)))        // header
        for total in ["小計 ¥451,500", "合計 ¥451,500", "お預り ¥460,000", "お釣り ¥8,500"] {
            #expect(selected.contains(total))
        }
        #expect(selected.contains("商品300 ※ ¥3000"))      // just above the totals
        #expect(!selected.contains("商品1 ※ ¥10"))          // far from the totals
        // Order is kept.
        let indices = selected.map { lines.firstIndex(of: $0)! }
        #expect(indices == indices.sorted())
    }

    @Test func longReceiptWithoutTotalsSendsTheTop() {
        let lines = (1...500).map { "行\($0)" }
        let selected = ModelLineSelector.select(lines, budget: 100)
        #expect(selected.first == "行1")
        #expect(selected.reduce(0) { $0 + $1.count + 1 } <= 100)
    }

    @Test func defaultBudgetFitsTypicalReceipts() {
        let typical = (1...40).map { "商品名サンプル\($0) ※ ¥1,234" }
        #expect(ModelLineSelector.select(typical) == typical)
    }
}

@Suite struct RefinerPromptTests {
    @Test func instructionsCoverJapaneseReceiptRules() {
        let text = RefinerPrompt.instructions
        for rule in ["合計", "お預り", "お釣り", "令和", "2018", "※", "English"] {
            #expect(text.contains(rule), "instructions should mention \(rule)")
        }
    }
}

/// Runs the real on-device model. Only where Apple Intelligence is available.
@Suite(.enabled(if: FoundationModelsRefiner.isAvailable, "Apple Intelligence not available"))
struct FoundationModelsLiveTests {
    @Test(.timeLimit(.minutes(1)))
    func refinesSampleReceipt() async {
        let lines = ["サンプルマート 中野店", "令和8年11月3日(火) 18:42", "牛乳 ※ ¥198", "食パン ※ ¥158", "洗剤 ¥398",
                     "小計 ¥754", "(内消費税等 ¥67)", "合計 ¥754", "お預り ¥1,000", "お釣り ¥246"]
        let draft = ReceiptParser.parse(lines: lines, today: today)
        let refined = await FoundationModelsRefiner(timeLimit: .seconds(30)).refine(lines: lines, draft: draft)
        print("Refined items:", refined.items.map { "\($0.name) / \($0.nameEn ?? "-") / \($0.priceYen)" })
        #expect(refined.totalYen == 754)
        #expect(refined.confidence(for: .totalYen) == .high)
    }
}
