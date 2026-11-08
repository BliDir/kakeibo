import Foundation
import Testing
@testable import KakeiboCore

/// BI-06: the facts the wording model gets, and the check its sentence must pass.
@Suite struct InsightSummaryTests {
    private struct Item: InsightItem {
        var dayKey: String
        var totalYen: Int
        var category: ExpenseCategory
        var storeName: String
        var tax10Yen: Int? = nil
        var tax8Yen: Int? = nil
    }

    private static let november = LedgerMonth(year: 2026, month: 11)
    private static let midNovember = Calendar.kakeibo.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 12))!

    /// Groceries ¥30,000 and dining ¥10,000 a month from August to October; November has
    /// dining well above usual and one ¥20,000 purchase at ニトリ, over a ¥40,000 budget.
    private static func overAnalysis(language: AppLanguage = .en) -> OverspendAnalysis {
        var history: [Item] = []
        for m in ["2026-08", "2026-09", "2026-10"] {
            for d in ["05", "12", "19"] { history.append(Item(dayKey: "\(m)-\(d)", totalYen: 10_000, category: .groceries, storeName: "西友")) }
            for d in ["03", "10", "17", "24"] { history.append(Item(dayKey: "\(m)-\(d)", totalYen: 2_500, category: .dining, storeName: "喫茶ポエム")) }
        }
        let items = [
            Item(dayKey: "2026-11-05", totalYen: 7_500, category: .groceries, storeName: "西友"),
            Item(dayKey: "2026-11-12", totalYen: 7_500, category: .groceries, storeName: "西友"),
            Item(dayKey: "2026-11-02", totalYen: 4_000, category: .dining, storeName: "喫茶ポエム"),
            Item(dayKey: "2026-11-09", totalYen: 4_000, category: .dining, storeName: "喫茶ポエム"),
            Item(dayKey: "2026-11-10", totalYen: 20_000, category: .household, storeName: " ニトリ "),
        ]
        return OverspendAnalysis(month: november, budget: .yen(40_000), items: items, history: history, now: midNovember)
    }

    private static let facts = InsightSummaryFacts(
        language: .en, situation: .overBudget, budgetYen: 40_000, spentYen: 52_400, overYen: 12_400,
        drivers: [
            .init(kind: .categoryIncrease, name: "Dining out", yen: 8_400),
            .init(kind: .moreVisits, name: "7-Eleven 3丁目店", yen: 1_600, visits: 14, usualVisits: 8),
        ])

    private static let factsJa = InsightSummaryFacts(
        language: .ja, situation: .overBudget, budgetYen: 40_000, spentYen: 52_400, overYen: 12_400,
        drivers: [.init(kind: .largeOneOff, name: "ニトリ", yen: 20_000)])

    private func check(_ text: String, _ facts: InsightSummaryFacts = Self.facts) -> Result<String, InsightSentenceCheck.Rejection> {
        InsightSentenceCheck.validate(text, facts: facts)
    }

    // MARK: Facts

    @Test func factsComeFromTheStructuredDriversOnly() throws {
        let analysis = Self.overAnalysis()
        let facts = try #require(InsightSummaryFacts(analysis, language: .en))
        #expect(facts.situation == .overBudget)
        #expect(facts.budgetYen == 40_000)
        #expect(facts.spentYen == 43_000)
        #expect(facts.overYen == 3_000)
        #expect(facts.projectedYen == nil)
        #expect(facts.drivers.count == analysis.drivers.count)
        let oneOff = try #require(facts.drivers.first { $0.kind == .largeOneOff })
        #expect(oneOff.name == "ニトリ")          // trimmed saved name
        #expect(oneOff.yen == 20_000)
        #expect(facts.figures.contains(1))      // "one purchase"
        #expect(facts.figures.isSuperset(of: [40_000, 43_000, 3_000, 20_000]))
    }

    @Test func factsUseTheUILanguageForCategories() throws {
        let en = try #require(InsightSummaryFacts(Self.overAnalysis(), language: .en))
        let ja = try #require(InsightSummaryFacts(Self.overAnalysis(), language: .ja))
        let enDining = en.drivers.first { $0.kind == .categoryIncrease }?.name
        let jaDining = ja.drivers.first { $0.kind == .categoryIncrease }?.name
        #expect(enDining == ExpenseCategory.dining.displayName(for: .en))
        #expect(jaDining == ExpenseCategory.dining.displayName(for: .ja))
        #expect(ja.language == .ja)
    }

    @Test func noFactsInLimitedHistory() {
        let items = [Item(dayKey: "2026-11-05", totalYen: 45_000, category: .groceries, storeName: "西友")]
        let analysis = OverspendAnalysis(month: Self.november, budget: .yen(40_000), items: items, history: [Item](),
                                         now: Self.midNovember)
        #expect(analysis.isLimitedHistory)
        #expect(InsightSummaryFacts(analysis, language: .en) == nil)
    }

    // MARK: Accepted

    @Test func acceptsASentenceWhoseNumbersAllMatch() {
        #expect(check("You're ¥12,400 over, mostly from dining out (¥8,400 above usual) and 14 visits to 7-Eleven 3丁目店 vs 8 usual.")
            == .success("You're ¥12,400 over, mostly from dining out (¥8,400 above usual) and 14 visits to 7-Eleven 3丁目店 vs 8 usual."))
    }

    @Test func acceptsJapaneseWithFullWidthDigitsAndOnePurchase() {
        #expect(check("ニトリでの一回の買い物（２０,０００円）が、予算を12,400円超えた主な理由です。", Self.factsJa).isSuccess)
        #expect(check("One purchase at ニトリ of ¥20,000 explains most of this month's ¥12,400 overspend.",
                      InsightSummaryFacts(language: .en, situation: .overBudget, budgetYen: 40_000, spentYen: 52_400,
                                          overYen: 12_400, drivers: [.init(kind: .largeOneOff, name: "ニトリ", yen: 20_000)])).isSuccess)
    }

    @Test func stripsQuotesAndSpaces() {
        #expect(check("  “Dining out is ¥8,400 above usual this month.”\n") == .success("Dining out is ¥8,400 above usual this month."))
    }

    // MARK: Rejected

    @Test func rejectsAWrongNumber() {
        #expect(check("Dining out is ¥8,500 above usual.") == .failure(.unknownNumber("8,500")))
        #expect(check("Dining out is ¥8,400 above usual and you're ¥12,000 over.") == .failure(.unknownNumber("12,000")))
    }

    @Test func rejectsAnExtraNumber() {
        // 3 is in no input figure (the store name's 3 is allowed only inside the name).
        #expect(check("Dining out is ¥8,400 above usual across 3 weeks.") == .failure(.unknownNumber("3")))
        #expect(check("Dining out is ¥8,400 above usual, about 21% of the overspend.") == .failure(.unknownNumber("21")))
    }

    @Test func rejectsRoundedOrRegroupedNumbers() {
        #expect(check("Dining out is ¥8.4 thousand above usual.") == .failure(.unknownNumber("8.4")))
        #expect(check("Dining out is ¥84,00 above usual.") == .failure(.unknownNumber("84,00")))
        // 1万2,400円: the 1 is allowed ("one purchase"), the 2,400 is not a figure.
        #expect(check("ニトリは通常より1万2,400円多いです。", Self.factsJa) == .failure(.unknownNumber("2,400")))
    }

    @Test func rejectsNumbersInWords() {
        #expect(check("Dining out is about eight thousand yen above usual.") == .failure(.spelledNumber("thousand")))
        #expect(check("Dining out is ¥8,400 above usual over five days.") == .failure(.spelledNumber("five")))
        #expect(check("You're ¥12,400 over, twice the usual.") == .failure(.spelledNumber("twice")))
        #expect(check("You're ¥12,400 over, ¥8,400k from dining out.") == .failure(.spelledNumber("k")))
        #expect(check("予算を約二万円超えています。", Self.factsJa) == .failure(.spelledNumber("二")))
        // "One purchase" needs a large one-off among the drivers.
        #expect(check("One reason is dining out, ¥8,400 above usual.") == .failure(.spelledNumber("one")))
    }

    @Test func rejectsTooLong() {
        let long = "Dining out is ¥8,400 above usual" + String(repeating: " and more", count: 20) + "."
        #expect(long.count > InsightSentenceCheck.maximumLength(for: .en))
        #expect(check(long) == .failure(.tooLong))
        let longJa = "ニトリでの買い物が20,000円で" + String(repeating: "、とても", count: 20) + "多いです。"
        #expect(check(longJa, Self.factsJa) == .failure(.tooLong))
    }

    @Test func rejectsMoreThanOneSentence() {
        #expect(check("Dining out is ¥8,400 above usual. Try cooking at home.") == .failure(.notOneSentence))
        #expect(check("Dining out is up.\nKeep going.") == .failure(.notOneSentence))
        #expect(check("ニトリで20,000円でした。今月は多めです。", Self.factsJa) == .failure(.notOneSentence))
        #expect(check("   ") == .failure(.empty))
    }

    @Test func rejectsTheWrongLanguage() {
        #expect(check("外食が通常より8,400円多いです。") == .failure(.wrongLanguage))
        #expect(check("Nitori: ¥20,000.", Self.factsJa) == .failure(.wrongLanguage))
        // A Japanese store name inside an English sentence is fine.
        #expect(check("Most of it is one purchase at ニトリ, ¥20,000.",
                      InsightSummaryFacts(language: .en, situation: .overBudget, budgetYen: 40_000, spentYen: 52_400,
                                          overYen: 12_400, drivers: [.init(kind: .largeOneOff, name: "ニトリ", yen: 20_000)])).isSuccess)
    }

    @Test func rejectsASentenceWithoutFigures() {
        #expect(check("Dining out is well above usual this month.") == .failure(.noFigures))
        // A digit inside a store name is not a figure.
        #expect(check("Most of it is visits to 7-Eleven 3丁目店.") == .failure(.noFigures))
    }

    @Test func rejectsJudgement() {
        #expect(check("You wasted ¥8,400 on dining out.") == .failure(.judgement))
        #expect(check("ニトリで20,000円の無駄遣いがありました。", Self.factsJa) == .failure(.judgement))
    }
}

private extension Result {
    var isSuccess: Bool { if case .success = self { true } else { false } }
}
