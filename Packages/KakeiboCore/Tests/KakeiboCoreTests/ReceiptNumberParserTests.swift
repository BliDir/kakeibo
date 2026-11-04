import Testing
@testable import KakeiboCore

@Suite struct ReceiptNumberParserTests {
    private func parse(_ text: String) -> ReceiptNumberParser.Result? {
        ReceiptNumberParser.parse(lines: TextNormalizer.normalize(text: text))
    }

    @Test(arguments: [
        ("レシートNo.1234", "1234"),
        ("レシートNO 0012-3456", "0012-3456"),
        ("レシート番号: 000123", "000123"),
        ("取引番号 000123", "000123"),
        ("取引No.4567", "4567"),
        ("伝票番号 0042", "0042"),
        ("伝票No 4567", "4567"),
        ("ﾚｼｰﾄＮｏ．１２３４", "1234"),   // half-width katakana, full-width digits
    ])
    func labelledNumbers(line: String, expected: String) throws {
        let r = try #require(parse(line))
        #expect(r.receiptNumber == expected)
        #expect(r.confidence == .high)
    }

    @Test func bareNumberIsMedium() throws {
        let r = try #require(parse("No.0012-3456"))
        #expect(r.receiptNumber == "0012-3456")
        #expect(r.confidence == .medium)
    }

    @Test func registerOnTheSameLine() throws {
        #expect(parse("レジ1 No.2345")?.receiptNumber == "1/2345")
        #expect(parse("レジ02 担当:山田 レシートNo.0012")?.receiptNumber == "02/0012")
        #expect(parse("レジNo.3 取引番号 777")?.receiptNumber == "3/777")
    }

    @Test func registerOnANearbyLine() throws {
        let r = try #require(parse("""
        ローソン 中野坂上店
        2026年11月3日 7:52
        レジ#02
        取引番号 000123
        合計 ¥378
        """))
        #expect(r.receiptNumber == "02/000123")
    }

    @Test func labelledNumberWinsOverBareNumber() throws {
        let r = try #require(parse("No.99\nレシートNo.1234"))
        #expect(r.receiptNumber == "1234")
    }

    @Test(arguments: [
        "会員No.123456",
        "カードNo.1234",
        "承認No.482913",
        "端末No.12",
        "店No.0123",
        "担当No.5",
        "TEL No.03-1234-5678",
        "登録番号 T1234567890123",
        "Kinokuniya 合計 ¥500",
        "ポイントNo.0000",
        "合計 ¥378",
    ])
    func otherNumbersAreNotReceiptNumbers(line: String) {
        #expect(parse(line) == nil)
    }

    @Test func comparisonKeyIgnoresLeadingZeros() {
        #expect(ReceiptNumberParser.comparisonKey("02/0012") == ReceiptNumberParser.comparisonKey("2/12"))
        #expect(ReceiptNumberParser.comparisonKey("0012-3456") == "12-3456")
        #expect(ReceiptNumberParser.comparisonKey("0000") == "0")
        #expect(ReceiptNumberParser.comparisonKey("1/2345") != ReceiptNumberParser.comparisonKey("2/2345"))
        #expect(ReceiptNumberParser.comparisonKey("") == nil)
    }

    @Test func parserFillsDraft() {
        let draft = ReceiptParser.parse(text: "ローソン\nレジ1 No.2345\n合計 ¥378", today: .now)
        #expect(draft.receiptNumber == "1/2345")
        #expect(draft.confidence(for: .receiptNumber) == .medium)
    }
}
