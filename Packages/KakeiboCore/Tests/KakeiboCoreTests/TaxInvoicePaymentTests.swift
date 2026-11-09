import Testing
@testable import KakeiboCore

private func lines(_ text: String) -> [String] { TextNormalizer.normalize(text: text) }

@Suite struct TaxExtractorTests {
    private func tax(_ text: String, total: Int? = nil) -> TaxExtractor.Result? {
        TaxExtractor.extract(lines: lines(text), totalYen: total)
    }

    @Test func externalTaxByRate() throws {
        let r = try #require(tax("""
        小計 ¥754
        外税8%対象 ¥356
        外税8% ¥28
        外税10%対象 ¥398
        外税10% ¥39
        合計 ¥821
        """, total: 821))
        #expect(r.tax8Yen == 28)
        #expect(r.tax10Yen == 39)
        #expect(r.confidence == .high)
    }

    @Test func internalTaxOnSameLineAsTaxableAmount() throws {
        let r = try #require(tax("""
        (10%対象 ¥1,100 内税 ¥100)
        (8%対象 ¥540 内税 ¥40)
        """))
        #expect(r.tax10Yen == 100)
        #expect(r.tax8Yen == 40)
    }

    @Test(arguments: [
        ("標準税率 10% 消費税 ¥91", 91, nil),
        ("消費税(標準) ¥91", 91, nil),
        ("軽減税率 8% 消費税等 ¥37", nil, 37),
        ("消費税(軽減) ¥37", nil, 37),
        ("10%税 ¥91", 91, nil),
        ("内消費税等 10% ¥91", 91, nil),
    ] as [(String, Int?, Int?)])
    func readsRateFromLine(line: String, ten: Int?, eight: Int?) throws {
        let r = try #require(tax(line))
        #expect(r.tax10Yen == ten)
        #expect(r.tax8Yen == eight)
    }

    @Test func loneInternalTaxGoesToTenPercent() throws {
        let r = try #require(tax("合計 ¥1,320\n(内消費税 ¥120)"))
        #expect(r.tax10Yen == 120)
        #expect(r.tax8Yen == nil)
        #expect(r.confidence == .medium)
    }

    @Test func unratedTotalIgnoredWhenRatesExist() throws {
        let r = try #require(tax("消費税等 ¥67\n外税8% ¥28\n外税10% ¥39"))
        #expect(r.tax10Yen == 39)
        #expect(r.tax8Yen == 28)
    }

    @Test func bothRatesOnOneLine() throws {
        let r = try #require(tax("内税 10% ¥90 8% ¥37"))
        #expect(r.tax10Yen == 90)
        #expect(r.tax8Yen == 37)
    }

    @Test func ignoresTaxAtOrAboveTotal() {
        #expect(tax("消費税 ¥1,000", total: 1_000) == nil)
        #expect(tax("消費税 ¥2,000", total: 1_000) == nil)
        #expect(tax("消費税 ¥90", total: 1_000)?.tax10Yen == 90)
    }

    @Test(arguments: ["税込合計 ¥1,100", "10%対象 ¥1,000", "標準税率対象 ¥1,000", "非課税 ¥500",
                      "税抜 ¥1,000", "※は軽減税率対象商品",
                      "外税8%対象 ¥356", "外税対象額 ¥1,000"])
    func ignoresNonTaxLines(line: String) {
        #expect(tax(line) == nil)
    }

    /// B-13, Seiyu: the tax word on its own line, the rate and amount on the lines below.
    @Test func taxHeadingAboveRateLines() {
        let result = tax("""
        税抜金額対象
        8% 9点 ¥1,545
        消費税額
        8% 9点 ¥123
        合計 ¥1,668
        """, total: 1_668)
        #expect(result?.tax8Yen == 123)
        #expect(result?.tax10Yen == nil)
        #expect(result?.confidence == .high)
    }

    @Test func taxHeadingWithBothRates() {
        let result = tax("消費税等\n10% ¥90\n8% ¥37\n合計 ¥1,527", total: 1_527)
        #expect(result?.tax10Yen == 90)
        #expect(result?.tax8Yen == 37)
    }

    /// B-14, FamilyMart: the tax line has no rate; the 対象 line above it has.
    @Test func taxTakesTheRateOfTheTaxableLineAbove() {
        let result = tax("""
        合 計 ¥1,260
        (10%対象 ¥5)
        (内消費税等 ¥0)
        ( 8%対象 ¥1,255)
        (内消費税等 ¥92)
        """, total: 1_260)
        #expect(result?.tax10Yen == 0)
        #expect(result?.tax8Yen == 92)
        #expect(result?.confidence == .high)
    }

    /// B-14, Life: `外10% ¥284` is a tax line; its taxable line says 対象.
    @Test func lifeExternalRateLine() {
        let result = tax("(外10% 対象 ¥2,846)\n外10% ¥284\n合計 ¥3,130", total: 3_130)
        #expect(result?.tax10Yen == 284)
        #expect(result?.tax8Yen == nil)
    }

    /// B-14, 7-Eleven: the closing 内消費税等 summary (¥74) includes tax inside `490込` items;
    /// the earlier 消費税等(10%) (¥30) is only the tax added on top.
    @Test func lastTaxLinePerRateWins() {
        let result = tax("""
        消費税等( 8%) ¥21
        消費税等(10%) ¥30
        合 計 ¥1,161
        (内消費税等 8% ¥21)
        (内消費税等10% ¥74)
        """, total: 1_161)
        #expect(result?.tax8Yen == 21)
        #expect(result?.tax10Yen == 74)
    }

    /// A rate line after something else (a taxable base) is not a tax amount.
    @Test func rateLineWithoutHeadingIsNotTax() {
        #expect(tax("10% ¥1,000\n合計 ¥1,100", total: 1_100) == nil)
    }
}

@Suite struct InvoiceNumberParserTests {
    @Test(arguments: [
        "登録番号 T1234567890123",
        "登録番号:T1234567890123",
        "登録番号 T1234-5678-9012-3",
        "登録番号 T 1234 5678 9012 3",
        "登録番号 T-1234567890123",
        "登録番号 Ｔ１２３４５６７８９０１２３",
        "適格請求書発行事業者 T1234567890123",
    ])
    func readsInvoiceNumber(line: String) throws {
        let r = try #require(InvoiceNumberParser.parse(lines: lines(line)))
        #expect(r.invoiceNumber == "T1234567890123")
        #expect(r.confidence == .high)
    }

    @Test func unlabelledNumberIsMedium() throws {
        let r = try #require(InvoiceNumberParser.parse(lines: ["T9876543210987"]))
        #expect(r.invoiceNumber == "T9876543210987")
        #expect(r.confidence == .medium)
    }

    @Test func labelledLineWins() throws {
        let r = try #require(InvoiceNumberParser.parse(lines: ["T9876543210987", "登録番号 T1234567890123"]))
        #expect(r.invoiceNumber == "T1234567890123")
    }

    @Test(arguments: ["T123456789012", "T12345678901234", "TEL 03-1234-5678", "AT1234567890123", "1234567890123"])
    func rejectsWrongLength(line: String) {
        #expect(InvoiceNumberParser.parse(lines: [line]) == nil)
    }
}

@Suite struct PaymentMethodDetectorTests {
    private func pay(_ text: String) -> PaymentMethodDetector.Result {
        PaymentMethodDetector.detect(lines: lines(text))
    }

    @Test(arguments: ["PayPay ¥596", "PAYPAY支払", "楽天ペイ ¥500", "d払い ¥500", "au PAY ¥500", "auPAY", "メルペイ ¥500"])
    func qrPay(line: String) {
        #expect(pay(line) == .init(payment: .qrPay, confidence: .high))
    }

    @Test(arguments: ["Suica ¥160", "SUICA残高 ¥1,234", "PASMO", "ICOCA", "iD ¥500", "QUICPay ¥500",
                      "nanaco支払 ¥500", "WAON ¥500", "交通系IC ¥160", "電子マネー ¥160"])
    func icCard(line: String) {
        #expect(pay(line) == .init(payment: .icCard, confidence: .high))
    }

    @Test(arguments: ["クレジット ¥1,320", "VISA ¥1,320", "Mastercard", "MASTER", "JCB", "AMEX", "American Express"])
    func credit(line: String) {
        #expect(pay(line) == .init(payment: .credit, confidence: .high))
    }

    @Test func cashByChange() {
        #expect(pay("お預り ¥1,000\nお釣り ¥640\nクレジットカード使えます") == .init(payment: .cash, confidence: .high))
    }

    @Test func zeroChangeDoesNotForceCash() {
        #expect(pay("お預り PayPay ¥500\nお釣り ¥0").payment == .qrPay)
    }

    @Test func defaultIsLowConfidenceCash() {
        #expect(pay("合計 ¥500") == .init(payment: .cash, confidence: .low))
    }

    @Test func pointLinesDoNotCount() {
        #expect(pay("合計 ¥500\nnanacoポイント 5P\nWAON POINT 10") == .init(payment: .cash, confidence: .low))
    }

    @Test func idNeedsExactCase() {
        #expect(pay("会員ID 12345").payment == .cash)
        #expect(pay("PAID").payment == .cash)
    }
}

@Suite struct InvoiceNumberWithoutTTests {
    private func parse(_ text: String) -> InvoiceNumberParser.Result? {
        InvoiceNumberParser.parse(lines: TextNormalizer.normalize(text: text))
    }

    @Test(arguments: [
        "登録番号 1234567890123",            // Vision dropped the T
        "登録番号:1234-5678-9012-3",
        "登録番号 1234 5678 9012 3",
        "登録NO 1234567890123",
        "適格請求書発行事業者 1234567890123",
        "登録番号 丁1234567890123",          // T read as 丁
        "登録番号 Т1234567890123",           // Cyrillic Т
        "登録番号 ㄒ1234567890123",
        "登録番号 †1234567890123",
    ])
    func labelledLineForgivesTheT(line: String) throws {
        let result = try #require(parse(line))
        #expect(result.invoiceNumber == "T1234567890123")
        #expect(result.confidence == .high)
    }

    @Test(arguments: ["登録番号\nT1234567890123", "登録番号:\n1234567890123", "適格請求書発行事業者登録番号\n1234-5678-9012-3"])
    func numberOnTheLineAfterABareLabel(text: String) throws {
        #expect(try #require(parse(text)).invoiceNumber == "T1234567890123")
    }

    @Test(arguments: [
        "4901234567894",                     // a JAN barcode
        "牛乳 4901234567894",
        "会員番号 1234567890123",            // labelled as something else
        "登録番号 123456789012",             // 12 digits
        "登録番号 12345678901234",           // 14 digits
    ])
    func rejectsUnlabelledOrWrongLength(line: String) {
        #expect(parse(line) == nil)
    }

    @Test func numberAfterLabelMustBeOnTheNextLineOnly() {
        #expect(parse("登録番号\n店長 山田\n1234567890123") == nil)
    }

    @Test func labelledWinsOverUnlabelled() throws {
        let result = try #require(parse("T9876543210987\n登録番号 1234567890123"))
        #expect(result.invoiceNumber == "T1234567890123")
    }
}
