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

/// B-15: a photo of a tightly printed receipt, tilted, as Vision reports it: axis-aligned boxes
/// around each rotated piece of text, each with its baseline slope.
@Suite struct LineBuilderTiltTests {
    /// The FamilyMart 六本木ヒルズ receipt: (left text, its x and width in pixels, price).
    static let rows: [(text: String, x: Double, width: Double, price: String?)] = [
        ("==========", 500, 1500, nil),
        ("領 収 証", 900, 600, nil),
        ("==========", 500, 1500, nil),
        ("◎大きいウインナー", 500, 1000, "¥170軽"),
        ("◎和風ツナパン", 500, 760, "¥150軽"),
        ("◎フランクロール", 500, 880, "¥210軽"),
        ("◎天然水新潟県津南60", 500, 1100, nil),
        ("@118× 2点", 700, 560, "¥236軽"),
        ("レジ袋20号バイオマス", 500, 1150, "¥5"),
        ("メキシカンサラダラップ", 500, 1200, "¥498軽"),
        ("チョコクリームたい焼き", 500, 1200, "¥200軽"),
        ("合 計", 500, 300, "¥1,469"),
        ("(10%対象", 500, 520, "¥5)"),
        ("(内消費税等", 500, 600, "¥0)"),
        ("( 8%対象", 500, 520, "¥1,464)"),
        ("(内消費税等", 500, 600, "¥108)"),
        ("クレジット支払", 500, 700, "¥1,469"),
    ]

    static let expected = rows.map { row in row.price.map { "\(row.text) \($0)" } ?? row.text }

    /// A 3024 × 4032 photo. Rows are `pitch` × the text height apart; prices are printed
    /// `raise` × the text height above the name's baseline; the paper is turned `degrees`
    /// (positive: clockwise, rows run down to the right).
    static func photo(degrees: Double, pitch: Double = 1.15, raise: Double = 0.25,
                      baselines: Bool = true) -> [TextObservation] {
        let (w, h) = (3024.0, 4032.0)
        let textHeight = 62.0
        let angle = degrees * .pi / 180
        let (cx, cy) = (w / 2, h / 2)
        func observation(_ text: String, x: Double, top: Double, width: Double) -> TextObservation {
            // Rotate the text's centre about the page centre; the box encloses the turned text.
            let (mx, my) = (x + width / 2 - cx, top + textHeight / 2 - cy)
            let rx = cx + mx * cos(angle) - my * sin(angle)
            let ry = cy + mx * sin(angle) + my * cos(angle)
            let boxW = width * abs(cos(angle)) + textHeight * abs(sin(angle))
            let boxH = width * abs(sin(angle)) + textHeight * abs(cos(angle))
            return TextObservation(
                text: text,
                boundingBox: BoundingBox(x: (rx - boxW / 2) / w, y: (ry - boxH / 2) / h, width: boxW / w, height: boxH / h),
                confidence: 0.9,
                slope: baselines ? tan(angle) * w / h : nil
            )
        }
        var result: [TextObservation] = []
        for (index, row) in rows.enumerated() {
            let top = 1200 + Double(index) * pitch * textHeight
            result.append(observation(row.text, x: row.x, top: top, width: row.width))
            if let price = row.price {
                let width = Double(price.count) * 55
                result.append(observation(price, x: 2600 - width, top: top - raise * textHeight, width: width))
            }
        }
        // Vision often lists every name first, then every price.
        return result.sorted { ($0.boundingBox.midX > 0.6 ? 1 : 0, $0.boundingBox.minY) < ($1.boundingBox.midX > 0.6 ? 1 : 0, $1.boundingBox.minY) }
    }

    @Test(arguments: [0.0, 2, -2, 4, -4])
    func tightRowsOnATiltedPhoto(degrees: Double) {
        #expect(LineBuilder.lines(from: Self.photo(degrees: degrees)) == Self.expected)
    }

    @Test(arguments: [2.0, 4])
    func tighterRowsAndHigherPrices(degrees: Double) {
        #expect(LineBuilder.lines(from: Self.photo(degrees: degrees, pitch: 1.1, raise: 0.35)) == Self.expected)
    }

    /// The old grouping put each price on the row above at this tilt (the bug).
    @Test func driftOfMoreThanOneRow() {
        let observations = Self.photo(degrees: 4)
        let first = observations.min { $0.boundingBox.minY < $1.boundingBox.minY }!
        // Across the page the right column runs more than a row lower than the left.
        #expect(LineBuilder.baselineSlope(observations)! * 0.5 > 1.15 * 62 / 4032)
        #expect(first.text == "==========")
    }

    @Test func separatorRowsGetNoPrice() {
        let lines = LineBuilder.lines(from: Self.photo(degrees: 4))
        #expect(lines.filter { $0.hasPrefix("==") } == ["==========", "=========="])
    }

    /// Without baselines (older recordings) the side-by-side estimate still handles half a line.
    @Test func withoutBaselinesSmallTilt() {
        #expect(LineBuilder.lines(from: Self.photo(degrees: 0.7, baselines: false)) == Self.expected)
    }

    @Test(arguments: [2.0, 4, -4])
    func tiltedPhotoParsesToTheReceiptsItems(degrees: Double) {
        let lines = ["FamilyMart", "六本木ヒルズ店", "2026年11月 7日(土) 18:00"] + LineBuilder.lines(from: Self.photo(degrees: degrees))
        let draft = ReceiptParser.parse(lines: lines, today: Date(timeIntervalSince1970: 1_793_674_800))
        #expect(draft.totalYen == 1_469)
        #expect(draft.items.map(\.priceYen) == [170, 150, 210, 236, 5, 498, 200])
        #expect(draft.items.map(\.priceYen).reduce(0, +) == 1_469)
        #expect(draft.items[3].name == "天然水新潟県津南60")
        #expect(draft.confidence(for: .items) == .high)
    }

    @Test func baselineSlopeFavoursLongText() {
        let items = [
            TextObservation(text: "long name", boundingBox: BoundingBox(x: 0.1, y: 0.1, width: 0.5, height: 0.02), confidence: 1, slope: 0.05),
            TextObservation(text: "¥1", boundingBox: BoundingBox(x: 0.7, y: 0.1, width: 0.06, height: 0.02), confidence: 1, slope: -0.2),
            TextObservation(text: "¥2", boundingBox: BoundingBox(x: 0.7, y: 0.2, width: 0.06, height: 0.02), confidence: 1, slope: -0.2),
        ]
        #expect(LineBuilder.baselineSlope(items) == 0.05)
        #expect(LineBuilder.baselineSlope([]) == nil)
    }
}
