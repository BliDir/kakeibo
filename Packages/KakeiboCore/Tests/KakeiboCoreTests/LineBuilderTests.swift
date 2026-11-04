import Foundation
import Testing
@testable import KakeiboCore

/// Builds synthetic observations. `y` is the top of the box, `h` the height (normalized, top-left origin).
private func obs(_ text: String, x: Double, y: Double, w: Double = 0.2, h: Double = 0.03, c: Double = 0.9) -> TextObservation {
    TextObservation(text: text, boundingBox: BoundingBox(x: x, y: y, width: w, height: h), confidence: c)
}

@Suite struct LineBuilderTests {
    // MARK: Name and price pairs

    @Test func joinsNamesWithPricesEvenWhenVisionListsThemSeparately() {
        // Vision often returns every name first, then every price.
        let input = [
            obs("牛乳※", x: 0.05, y: 0.30), obs("食パン※", x: 0.05, y: 0.35), obs("洗剤", x: 0.05, y: 0.40),
            obs("¥198", x: 0.70, y: 0.301, w: 0.15), obs("¥158", x: 0.70, y: 0.349, w: 0.15), obs("¥398", x: 0.70, y: 0.402, w: 0.15),
        ]
        #expect(LineBuilder.lines(from: input) == ["牛乳※ ¥198", "食パン※ ¥158", "洗剤 ¥398"])
    }

    @Test func threeColumnRow() {
        let input = [
            obs("¥400", x: 0.75, y: 0.5, w: 0.12),
            obs("コーヒー", x: 0.05, y: 0.5),
            obs("x2", x: 0.45, y: 0.502, w: 0.06),
        ]
        #expect(LineBuilder.lines(from: input) == ["コーヒー x2 ¥400"])
    }

    @Test func singleColumnHeaderLinesStaySeparate() {
        let input = [
            obs("サンプルマート 中野店", x: 0.2, y: 0.05, w: 0.6, h: 0.04),
            obs("東京都中野区中野9-9-9", x: 0.15, y: 0.10, w: 0.7),
            obs("TEL 03-0000-0000", x: 0.25, y: 0.14, w: 0.5),
            obs("領収書", x: 0.4, y: 0.19, w: 0.2),
        ]
        #expect(LineBuilder.lines(from: input) == [
            "サンプルマート 中野店", "東京都中野区中野9-9-9", "TEL 03-0000-0000", "領収書",
        ])
    }

    @Test func ordersLinesTopToBottomAndWordsLeftToRight() {
        let input = [
            obs("C", x: 0.6, y: 0.8), obs("A", x: 0.1, y: 0.1), obs("D", x: 0.1, y: 0.8), obs("B", x: 0.6, y: 0.1),
        ]
        #expect(LineBuilder.lines(from: input) == ["A B", "D C"])
    }

    // MARK: Skew

    /// Rows `spacing` apart; the right column drifts by `drift` line heights.
    private func skewedReceipt(drift: Double, spacing: Double = 1.3) -> [TextObservation] {
        let h = 0.03
        return (0..<8).flatMap { row -> [TextObservation] in
            let top = 0.1 + Double(row) * spacing * h
            return [
                obs("品目\(row)", x: 0.05, y: top, w: 0.2, h: h),
                obs("¥\(row)00", x: 0.70, y: top + drift * h, w: 0.15, h: h),
            ]
        }
    }

    @Test(arguments: [0.5, -0.5, 0.3, -0.3])
    func toleratesHalfALineOfSkew(drift: Double) {
        let expected = (0..<8).map { "品目\($0) ¥\($0)00" }
        #expect(LineBuilder.lines(from: skewedReceipt(drift: drift)) == expected)
    }

    @Test func toleratesSkewOnATightlySpacedReceipt() {
        let expected = (0..<8).map { "品目\($0) ¥\($0)00" }
        #expect(LineBuilder.lines(from: skewedReceipt(drift: 0.5, spacing: 1.15)) == expected)
    }

    @Test func estimatesSlope() {
        // Right column 0.65 to the right of the left column, 0.5 × 0.03 lower.
        let slope = LineBuilder.estimateSlope(skewedReceipt(drift: 0.5))
        #expect(abs(slope - 0.015 / 0.65) < 0.002)
        #expect(LineBuilder.estimateSlope(skewedReceipt(drift: 0)) == 0)
    }

    // MARK: Edge cases

    @Test func differentHeightsOnOneLine() {
        // A large 合計 next to a normal-size price whose top is lower.
        let input = [obs("合計", x: 0.05, y: 0.70, h: 0.05), obs("¥754", x: 0.6, y: 0.71, w: 0.2, h: 0.04)]
        #expect(LineBuilder.lines(from: input) == ["合計 ¥754"])
    }

    @Test func dropsBlankObservations() {
        #expect(LineBuilder.lines(from: [obs(" ", x: 0.1, y: 0.1), obs("合計", x: 0.1, y: 0.2)]) == ["合計"])
        #expect(LineBuilder.lines(from: []).isEmpty)
    }

    @Test func lineConfidenceIsLowest() {
        let line = LineBuilder.build([obs("合計", x: 0.05, y: 0.5, c: 0.95), obs("¥754", x: 0.6, y: 0.5, c: 0.6)])
        #expect(line.count == 1)
        #expect(line[0].confidence == 0.6)
        #expect(line[0].observations.map(\.text) == ["合計", "¥754"])
    }

    // MARK: Real Vision output

    /// Observations recorded from Vision on KakeiboScan's sample receipt (T-20).
    private func recordedSample() throws -> [TextObservation] {
        let base = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let url = base.appendingPathComponent("ocr/sample-receipt.observations.json")
        return try JSONDecoder().decode([TextObservation].self, from: Data(contentsOf: url))
    }

    @Test func rebuildsRecordedVisionOutput() throws {
        #expect(LineBuilder.lines(from: try recordedSample()) == [
            "サンプルマート 中野店",
            "東京都中野区中野9-9-9",
            "2026年11月3日（火） 18:42",
            "登録番号 1234567890123",
            "牛乳※ ¥198",
            "食パン※ ¥158",
            "洗剤 ¥398",
            "小計 ¥754",
            "（内消費税等 ¥67）",
            "合計 ¥754",
            "お預り ¥1,000",
            "お釣り ¥246",
        ])
    }

    @Test func recordedVisionOutputParses() throws {
        let draft = ReceiptParser.parse(lines: LineBuilder.lines(from: try recordedSample()),
                                        today: Date(timeIntervalSince1970: 1_793_674_800))
        #expect(draft.totalYen == 754)
        #expect(draft.confidence(for: .totalYen) == .high)   // お預り − お釣り = 合計
        #expect(draft.dayKey == "2026-11-03")
        #expect(draft.time == "18:42")
        #expect(draft.tax10Yen == 67)
        #expect(draft.payment == .cash)
        // Vision dropped the T from 登録番号 (T-18).
        #expect(draft.invoiceNumber == "T1234567890123")
    }
}
