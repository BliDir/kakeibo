import Foundation
import Testing
@testable import KakeiboCore

@Suite struct ReceiptParserTests {
    static let today = Date(timeIntervalSince1970: 1_793_674_800) // 2026-11-03 12:00 Tokyo

    @Test func fillsFieldsAndConfidences() {
        let draft = ReceiptParser.parse(text: """
        ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店
        2026/11/03 08:15
        登録番号 T1234567890123
        合 計 \\360
        (内消費税等 10% ¥32)
        お預り ¥1,000
        お釣り ¥640
        """, today: Self.today)

        #expect(draft.storeName == "セブン-イレブン")
        #expect(draft.storeNameEn == "7-Eleven")
        #expect(draft.dayKey == "2026-11-03")
        #expect(draft.time == "08:15")
        #expect(draft.totalYen == 360)
        #expect(draft.tax10Yen == 32)
        #expect(draft.tax8Yen == nil)
        #expect(draft.payment == .cash)
        #expect(draft.category == .groceries)
        #expect(draft.invoiceNumber == "T1234567890123")
        #expect(draft.items.isEmpty)

        #expect(draft.confidence(for: .storeName) == .high)
        #expect(draft.confidence(for: .dayKey) == .high)
        #expect(draft.confidence(for: .time) == .medium)
        #expect(draft.confidence(for: .totalYen) == .high)   // お預り − お釣り matches
        #expect(draft.confidence(for: .tax10Yen) == .high)
        #expect(draft.confidences[.tax8Yen] == nil)
        #expect(draft.confidence(for: .payment) == .high)
        #expect(draft.confidence(for: .category) == .high)
        #expect(draft.confidence(for: .invoiceNumber) == .high)
    }

    @Test func emptyReceipt() {
        let draft = ReceiptParser.parse(lines: [], today: Self.today)
        #expect(draft.storeName == nil)
        #expect(draft.dayKey == nil)
        #expect(draft.totalYen == nil)
        #expect(draft.payment == .cash)
        #expect(draft.confidence(for: .payment) == .low)
        #expect(draft.category == .other)
        #expect(draft.confidence(for: .category) == .low)
        #expect(draft.confidences[.storeName] == nil)
        #expect(draft.confidences[.totalYen] == nil)
    }

    @Test func taxIsCheckedAgainstTotal() {
        // Without the total, ¥5,000 would be read as tax.
        let draft = ReceiptParser.parse(text: "合計 ¥500\n消費税 ¥5,000", today: Self.today)
        #expect(draft.tax10Yen == nil)
    }
}
