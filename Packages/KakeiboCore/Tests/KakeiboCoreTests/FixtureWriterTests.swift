import Foundation
import Testing
@testable import KakeiboCore

@Suite struct FixtureWriterTests {
    static let now = Date(timeIntervalSince1970: 1_793_674_800) // 2026-11-03 12:00 Tokyo

    @Test func nameUsesTokyoTimestamp() {
        #expect(FixtureWriter.name(at: Self.now) == "real-20261103-120000")
    }

    @Test func textIsOneRowPerLine() {
        #expect(FixtureWriter.text(lines: ["ローソン", "合計 ¥378"]) == "ローソン\n合計 ¥378\n")
    }

    @Test func expectedJSONMatchesTheHarnessFormat() throws {
        let draft = ReceiptDraft(
            storeName: "ローソン", dayKey: "2026-11-02", time: "07:52", totalYen: 378, tax10Yen: nil, tax8Yen: 28,
            payment: .icCard, category: .groceries, invoiceNumber: "T1234567890123",
            items: [LineItemDraft(name: "からあげクン", priceYen: 238, isReducedRate: true)]
        )
        let data = try FixtureWriter.expectedJSON(from: draft, scannedOn: Self.now)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["scannedOn"] as? String == "2026-11-03")
        #expect(object["storeName"] as? String == "ローソン")
        #expect(object["totalYen"] as? Int == 378)
        #expect(object["tax10Yen"] is NSNull)            // scored: expects nothing
        #expect(object["tax8Yen"] as? Int == 28)
        #expect(object["payment"] as? String == "icCard")
        #expect(object["category"] as? String == "groceries")
        let items = try #require(object["items"] as? [[String: Any]])
        #expect(items.first?["priceYen"] as? Int == 238)
        #expect(items.first?["isReducedRate"] as? Bool == true)
        // Readable for a human editing it.
        #expect(String(decoding: data, as: UTF8.self).contains("\n  \"category\" : \"groceries\""))
    }

    @Test func expectedJSONWritesNullForMissingFields() throws {
        let data = try FixtureWriter.expectedJSON(from: ReceiptDraft(totalYen: 500), scannedOn: Self.now)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["storeName", "dayKey", "time", "payment", "category", "invoiceNumber", "receiptNumber"] {
            #expect(object[key] is NSNull, "\(key)")
        }
        #expect((object["items"] as? [Any])?.isEmpty == true)
    }

    @Test func receiptNumberOnAMaskedLineIsExpectedMasked() throws {
        let lines = ["取引番号 001234", "合計 ¥500"]
        let draft = ReceiptDraft(totalYen: 500, receiptNumber: "001234")
        let data = try FixtureWriter.expectedJSON(from: draft, scannedOn: Self.now, lines: lines)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["receiptNumber"] as? String == "000000")
        // And the parser reads the same from the masked text.
        let parsed = ReceiptParser.parse(text: FixtureWriter.text(lines: lines), today: Self.now)
        #expect(parsed.receiptNumber == "000000")
    }

    @Test func receiptNumberOnAnUnmaskedLineIsKept() throws {
        let lines = ["レジ02 No.0012", "合計 ¥500"]
        let draft = ReceiptDraft(totalYen: 500, receiptNumber: "02/0012")
        let data = try FixtureWriter.expectedJSON(from: draft, scannedOn: Self.now, lines: lines)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["receiptNumber"] as? String == "02/0012")
    }

    // MARK: Redaction

    @Test(arguments: [
        ("会員番号 1234567890", "会員番号 0000000000"),
        ("ポイントカード No.98765", "ポイントカード No.00000"),
        ("承認番号 482913", "承認番号 000000"),
        ("伝票番号 0042", "伝票番号 0000"),
        ("VISA ************1234", "VISA ************0000"),
        ("カード番号 XXXX-XXXX-XXXX-5678", "カード番号 XXXX-XXXX-XXXX-0000"),
        ("4980 1234 5678 9012", "0000 0000 0000 0000"),
        ("お客様番号 12-34", "お客様番号 00-00"),
    ])
    func masksPersonalNumbers(line: String, expected: String) {
        #expect(FixtureWriter.redact([line]) == [expected])
    }

    @Test(arguments: [
        "登録番号 T1234567890123", "登録番号 1234567890123", "合計 ¥1,310", "2026/11/03 18:42", "TEL 03-1234-5678", "牛乳 ※ 198",
        "東京都中野区中野5-1-1", "お預り ¥10,000",
    ])
    func keepsWhatTheParserNeeds(line: String) {
        #expect(FixtureWriter.redact([line]) == [line])
    }

    @Test func redactedLinesStillParse() {
        let lines = FixtureWriter.redact(["ローソン", "2026/11/03 18:42", "会員番号 1234567890", "合計 ¥378", "Suica ¥378"])
        let draft = ReceiptParser.parse(lines: lines, today: Self.now)
        #expect(draft.totalYen == 378)
        #expect(draft.payment == .icCard)
    }
}
