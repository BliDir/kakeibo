import Testing
@testable import KakeiboCore

@Suite struct TotalExtractorTests {
    /// Runs the normalizer first, as the real pipeline does.
    private func extract(_ text: String, items: [Int] = []) -> TotalExtractor.Result? {
        TotalExtractor.extract(lines: TextNormalizer.normalize(text: text), itemPrices: items)
    }

    // MARK: Receipt types

    @Test func konbiniCashWithChange() throws {
        let r = try #require(extract("""
        セブン-イレブン 渋谷店
        2026年11月 3日(火) 8:15
        おにぎり 鮭 ※ ¥160
        コーヒー L ¥200
        小計 ¥360
        (8%対象 ¥160)
        (内消費税等 ¥32)
        合計 ¥360
        お預り ¥1,000
        お釣り ¥640
        """))
        #expect(r.totalYen == 360)
        #expect(r.confidence == .high)
        #expect(r.check == .change)
        #expect(r.tenderedYen == 1_000)
        #expect(r.changeYen == 640)
    }

    @Test func externalTaxSupermarket() throws {
        let r = try #require(extract("""
        マルエツ 中野店
        牛乳 198
        食パン 158
        洗剤 398
        小計 ¥754
        外税8%対象 ¥356
        外税8% ¥28
        外税10%対象 ¥398
        外税10% ¥39
        合計 ¥821
        クレジット ¥821
        """))
        #expect(r.totalYen == 821)
        #expect(r.check == .subtotalPlusTax)
        #expect(r.confidence == .high)
    }

    @Test func internalTaxCardPaymentIsKeywordOnly() throws {
        let r = try #require(extract("""
        マツモトキヨシ
        化粧水 ¥1,320
        合計 ¥1,320
        (内税10% ¥120)
        クレジット ¥1,320
        """))
        #expect(r.totalYen == 1_320)
        #expect(r.confidence == .medium)
        #expect(r.source == .totalLine)
    }

    @Test func discountsAndItemSum() throws {
        let r = try #require(extract("""
        イオン
        豚こま 498
        値引 -100
        キャベツ 198
        割引合計 -100
        合計 ¥596
        PayPay ¥596
        """, items: [498, -100, 198]))
        #expect(r.totalYen == 596)
        #expect(r.check == .itemSum)
        #expect(r.confidence == .high)
    }

    @Test func restaurantTotalWithPoints() throws {
        let r = try #require(extract("""
        すき家
        牛丼 並 ¥450
        合計 1点 ¥450
        ポイント利用 -50
        残高 ¥1,200
        お支払 ¥400
        """))
        #expect(r.totalYen == 450)
        #expect(r.confidence == .medium)
    }

    @Test func taxiWithAmountOnNextLine() throws {
        let r = try #require(extract("""
        日本交通
        乗車 22:41 降車 23:05
        ご請求額
        ¥3,280
        現金 ¥5,000
        お釣り ¥1,720
        """))
        #expect(r.totalYen == 3_280)
        #expect(r.check == .change)
    }

    // MARK: Keywords

    @Test(arguments: ["合計 ¥1,076", "お買上計 ¥1,076", "お買上げ ¥1,076", "御買上 ¥1,076",
                      "ご請求額 ¥1,076", "TOTAL ¥1,076", "Total 1,076", "合計 1,076円", "税込合計 ¥1,076"])
    func recognisesTotalKeywords(line: String) throws {
        #expect(try #require(extract(line)).totalYen == 1_076)
    }

    @Test(arguments: ["お預り ¥2,000", "お釣り ¥924", "点数 3", "合計点数 3点", "ポイント ¥50",
                      "残高 ¥4,000", "10%対象 ¥1,000", "外税対象額 ¥1,000", "お預り合計 ¥2,000"])
    func neverUsesExcludedLinesAsTotal(line: String) {
        let r = extract("合計 ¥777\n\(line)")
        #expect(r?.totalYen == 777)
    }

    @Test func excludedLineAloneGivesNoTotal() {
        #expect(extract("点数 3点\nポイント ¥50\n残高 ¥4,000") == nil)
    }

    @Test func subtotalIsNotATotal() throws {
        let r = try #require(extract("SUBTOTAL ¥900\nTOTAL ¥990"))
        #expect(r.totalYen == 990)
    }

    // MARK: Fallbacks

    @Test func subtotalFallbackWhenNoTotalLine() throws {
        let r = try #require(extract("小計 ¥540\nクレジット ¥540"))
        #expect(r.totalYen == 540)
        #expect(r.source == .subtotalFallback)
        #expect(r.confidence == .low)
    }

    @Test func subtotalFallbackConfirmedByChangeIsMedium() throws {
        let r = try #require(extract("小計 ¥540\nお預り ¥1,000\nお釣り ¥460"))
        #expect(r.source == .subtotalFallback)
        #expect(r.confidence == .medium)
        #expect(r.check == .change)
    }

    @Test func changeFallbackWhenNoTotalOrSubtotal() throws {
        let r = try #require(extract("お預り ¥1,000\nお釣り ¥120"))
        #expect(r.totalYen == 880)
        #expect(r.source == .changeFallback)
        #expect(r.confidence == .low)
    }

    @Test func nothingFound() {
        #expect(extract("ありがとうございました\nまたお越しください") == nil)
    }

    // MARK: Cross-check

    @Test func crossCheckPicksMatchingCandidate() throws {
        // Two total lines; only one matches お預り − お釣り.
        let r = try #require(extract("合計 ¥1,500\nお買上計 ¥1,350\nお預り ¥2,000\nお釣り ¥650"))
        #expect(r.totalYen == 1_350)
        #expect(r.check == .change)
    }

    @Test func crossCheckMismatchLowersConfidence() throws {
        let r = try #require(extract("合計 ¥1,076\nお預り ¥2,000\nお釣り ¥942"))
        #expect(r.totalYen == 1_076)
        #expect(r.confidence == .low)
        #expect(r.check == nil)
    }

    @Test func exactCashWithZeroChange() throws {
        let r = try #require(extract("合計 ¥500\nお預り ¥500\nお釣り ¥0"))
        #expect(r.check == .change)
        #expect(r.confidence == .high)
    }

    // MARK: Reading numbers

    @Test(arguments: [
        ("合計 ¥1,076", [1_076]),
        ("合計 3点 ¥1,076", [1_076]),
        ("10%対象 ¥1,000", [1_000]),
        ("2026/11/03 14:05 合計 ¥980", [980]),
        ("2026年11月3日 合計 980円", [980]),
        ("コーヒー x2 @120 ¥240", [240]),
        ("値引 -30", [-30]),
        ("値引 ▲30", [-30]),
        ("合計 12345678", []),
        ("合計 1,000 2,000", [1_000, 2_000]),
    ])
    func readsAmountsIgnoringTimesPercentagesAndCounts(line: String, expected: [Int]) {
        #expect(TotalExtractor.amounts(in: line) == expected)
    }

    @Test func totalLineUsesLastAmount() throws {
        #expect(try #require(extract("合計 3点 (8%) ¥1,076")).totalYen == 1_076)
    }

    @Test func nextLineMustBeBareAmount() {
        // The line after 合計 is お預り, so 合計 has no amount of its own.
        let r = extract("合計\nお預り ¥2,000\nお釣り ¥924")
        #expect(r?.source == .changeFallback)
        #expect(r?.totalYen == 1_076)
    }
}
