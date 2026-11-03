import Foundation
import Testing
@testable import KakeiboCore

@Suite struct StoreClassifierTests {
    private func classify(_ text: String) -> StoreClassifier.Result {
        StoreClassifier.classify(lines: TextNormalizer.normalize(text: text))
    }

    // MARK: Dictionary

    @Test func dictionaryLoadsWithAtLeastFiftyBrands() {
        let brands = StoreClassifier.chains.filter { !$0.isGeneric }
        #expect(brands.count >= 50)
        #expect(brands.allSatisfy { $0.name != nil && !$0.match.isEmpty })
        #expect(Set(brands.compactMap(\.name)).count == brands.count)
    }

    @Test(arguments: [
        ("まいばすけっと", ExpenseCategory.groceries), ("イオン", .groceries), ("西友", .groceries),
        ("ライフ", .groceries), ("オーケー", .groceries), ("サミット", .groceries),
        ("セブン-イレブン", .groceries), ("ファミリーマート", .groceries), ("ローソン", .groceries),
        ("スターバックス", .dining), ("ドトール", .dining), ("マクドナルド", .dining), ("吉野家", .dining),
        ("すき家", .dining), ("松屋", .dining), ("ガスト", .dining), ("サイゼリヤ", .dining),
        ("ENEOS", .transport), ("マツモトキヨシ", .household), ("ウエルシア", .household),
        ("ダイソー", .household), ("ニトリ", .household), ("無印良品", .household),
        ("西松屋", .kids), ("アカチャンホンポ", .kids),
        ("ユニクロ", .shopping), ("ビックカメラ", .shopping), ("ヨドバシカメラ", .shopping),
    ])
    func chainsFromIssueMapToCategory(name: String, category: ExpenseCategory) {
        let r = classify("\(name) 渋谷店\n2026/11/03")
        #expect(r.category == category)
        #expect(r.categoryConfidence == .high)
        #expect(r.storeName == name)
        #expect(r.storeConfidence == .high)
    }

    @Test(arguments: [
        ("JR東日本 新宿駅", ExpenseCategory.transport),
        ("日本交通タクシー", .transport),
        ("さくら調剤薬局", .health),
        ("みなと内科クリニック", .health),
        ("デンタルクリニック青山", .health),
    ])
    func genericKeywordsSetOnlyCategory(line: String, category: ExpenseCategory) {
        let r = classify("\(line)\n2026/11/03")
        #expect(r.category == category)
        #expect(r.categoryConfidence == .medium)
        #expect(r.storeName == TextNormalizer.normalizeLine(line))
        #expect(r.storeNameEn == nil)
        #expect(r.storeConfidence == .medium)
    }

    // MARK: Canonical names

    @Test(arguments: [
        ("ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ渋谷道玄坂店", "セブン-イレブン", "7-Eleven"),
        ("セブンイレブン 中野店", "セブン-イレブン", "7-Eleven"),
        ("FamilyMart 新宿店", "ファミリーマート", "FamilyMart"),
        ("ファミマ!! 東口店", "ファミリーマート", "FamilyMart"),
        ("LAWSON", "ローソン", "Lawson"),
        ("STARBUCKS COFFEE 渋谷", "スターバックス", "Starbucks"),
        ("株式会社西友 中野店", "西友", "Seiyu"),
        ("ドンキホーテ 新宿店", "ドン・キホーテ", "Don Quijote"),
        ("BIC CAMERA 有楽町", "ビックカメラ", "Bic Camera"),
        ("ライフ 中野店", "ライフ", "LIFE"),
    ])
    func brandSetsCanonicalAndEnglishName(line: String, name: String, nameEn: String) {
        let r = classify(line)
        #expect(r.storeName == name)
        #expect(r.storeNameEn == nameEn)
    }

    @Test func brandFoundBelowHeader() {
        // Logo printed as an image; the chain name appears only in the footer.
        let r = classify("""
        いらっしゃいませ
        渋谷道玄坂店
        おにぎり ¥160
        合計 ¥160
        株式会社ローソン
        """)
        #expect(r.storeName == "ローソン")
        #expect(r.category == .groceries)
    }

    // MARK: Word boundaries

    @Test(arguments: ["ライオン 歯磨き ¥298", "関西友の会", "PAYLAWSONS", "ガストロノミー"])
    func doesNotMatchInsideOtherWords(line: String) {
        let r = classify("やまだ商店\n\(line)")
        #expect(r.category == .other)
    }

    @Test func earliestLineWins() {
        let r = classify("ドトールコーヒーショップ\nセブン-イレブン銀座店")
        #expect(r.category == .dining)
    }

    // MARK: Store line heuristic

    @Test func skipsHeaderPhrasesAndAddresses() {
        let r = classify("""
        領収書
        いらっしゃいませ
        東京都渋谷区道玄坂1-2-3
        TEL 03-1234-5678
        やまだ商店
        2026/11/03
        """)
        #expect(r.storeName == "やまだ商店")
        #expect(r.storeConfidence == .medium)
    }

    @Test func skipsLinesWithMoreDigitsThanLetters() {
        #expect(classify("2026/11/03 18:42\nNo.1234567 店\n喫茶ポエム").storeName == "喫茶ポエム")
    }

    @Test func needsTwoLetters() {
        #expect(classify("A\n*\n喫茶ポエム").storeName == "喫茶ポエム")
    }

    @Test func onlyTopSixLines() {
        let text = (1...6).map { "\($0)" }.joined(separator: "\n") + "\n喫茶ポエム"
        #expect(classify(text).storeName == nil)
        #expect(classify(text).storeConfidence == .low)
    }

    @Test func latinHeaderWordsAreWholeWords() {
        #expect(classify("APA HOTEL 新宿").storeName == "APA HOTEL 新宿")
        #expect(classify("TEL 03-1234-5678\n喫茶ポエム").storeName == "喫茶ポエム")
    }

    @Test func unknownStoreIsOtherWithLowConfidence() {
        let r = classify("喫茶ポエム\n2026/11/03\n合計 ¥800")
        #expect(r.category == .other)
        #expect(r.categoryConfidence == .low)
        #expect(r.storeName == "喫茶ポエム")
        #expect(r.storeNameEn == nil)
    }
}
