import Testing
@testable import KakeiboCore

@Suite struct ItemParserTests {
    private func items(_ text: String) -> [LineItemDraft] {
        ItemParser.parse(lines: TextNormalizer.normalize(text: text))
    }

    private func prices(_ text: String) -> [Int] { items(text).map(\.priceYen) }

    @Test func readsItemsBetweenHeaderAndTotals() {
        let result = items("""
        セブン-イレブン 渋谷店
        東京都渋谷区道玄坂2-10-7
        TEL 03-0000-0000
        2026年11月 3日(火) 08:15
        登録番号 T1111111111111
        おにぎり 鮭 ※ ¥160
        ホットコーヒー L ¥200
        小計 ¥360
        合計 ¥360
        お預り ¥1,000
        """)
        #expect(result.map(\.name) == ["おにぎり鮭", "ホットコーヒー L"])
        #expect(result.map(\.priceYen) == [160, 200])
        #expect(result.map(\.isReducedRate) == [true, false])
    }

    @Test(arguments: [
        ("牛乳 198", 198), ("牛乳 ¥198", 198), ("牛乳 198円", 198), ("化粧水 ¥1,320", 1_320),
        ("牛乳 198 ※", 198), ("牛乳 198軽", 198), ("レジ袋 ¥5", 5),
    ])
    func readsPriceFormats(line: String, price: Int) {
        #expect(prices(line) == [price])
    }

    @Test(arguments: ["2026/10/28(火) 19:02", "レジ#2 0012", "乗車 23:05 降車 23:31", "レジ1 No.2345", "TEL 03-0000-0001",
                      "東京都中野区本町1-1-1", "テーブル 14 人数 2", "単価 ¥178", "登録番号 T1234567890123",
                      "(8%対象 ¥378 内消費税 ¥28)", "ポイント 5", "11月2日(月) 14:05",
                      "取引番号 0381", "取引No4567", "レシート番号 000123", "レシートNo1234"])
    func skipsHeaderAndInfoLines(line: String) {
        #expect(items(line).isEmpty)
    }

    @Test func smallNumbersWithoutYenAreNotPrices() {
        #expect(items("人 2").isEmpty)
        #expect(prices("袋 ¥3") == [3])
    }

    // MARK: Reduced rate

    @Test(arguments: [("※牛乳 198", true), ("牛乳★ 198", true), ("牛乳 198 軽", true), ("牛乳 軽 198", true),
                      ("軽食セット 500", false), ("洗剤 398", false)])
    func reducedRateMarks(line: String, reduced: Bool) {
        #expect(items(line).first?.isReducedRate == reduced)
    }

    @Test func marksAreRemovedFromNames() {
        #expect(items("※牛乳★ 198 軽").first?.name == "牛乳")
        #expect(items("軽食セット 500").first?.name == "軽食セット")
        #expect(items("牛乳 軽 198").first?.name == "牛乳")
    }

    // MARK: Quantity lines

    @Test func quantityUnderPricedItemKeepsTheItem() {
        let result = items("牛乳 ※ ¥396\n2コ × 198\n合計 ¥396")
        #expect(result.map(\.priceYen) == [396])
        #expect(result.first?.isReducedRate == true)
    }

    @Test func quantityCompletesANameWithoutPrice() {
        let result = items("バナナ ※\n3点 × @98 ¥294\n合計 ¥294")
        #expect(result.map(\.name) == ["バナナ"])
        #expect(result.map(\.priceYen) == [294])
        #expect(result.first?.isReducedRate == true)
    }

    @Test func quantityWithoutPrintedTotalMultiplies() {
        #expect(prices("コーヒー\n@120 x 2\n合計 ¥240") == [240])
        #expect(prices("コーヒー\n2個 x 120\n合計 ¥240") == [240])
    }

    // MARK: Discounts

    @Test func discountsAreNegativeAndTakeTheRateOfTheItemAbove() {
        let result = items("""
        豚こま切落し ※ 498
        値引 -100
        洗剤 398
        クーポン ▲50
        割引 30
        合計 ¥716
        """)
        #expect(result.map(\.priceYen) == [498, -100, 398, -50, -30])
        #expect(result.map(\.isReducedRate) == [true, true, false, false, false])
        #expect(result[1].name == "値引")
    }

    @Test func discountTotalsBelowTheTotalAreNotItems() {
        // 値引合計 is after 小計, outside the item region.
        #expect(prices("牛乳 198\n小計 ¥198\n値引合計 -20\n合計 ¥178") == [198])
    }

    @Test func noTotalLineReadsAllLines() {
        #expect(prices("牛乳 198\n食パン 158") == [198, 158])
    }
}

/// B-13: Seiyu prints a letter after each price (`¥199C`) and a department code before names.
@Suite struct ItemParserMarkTests {
    private func items(_ text: String) -> [LineItemDraft] {
        ItemParser.parse(lines: TextNormalizer.normalize(text: text))
    }

    @Test(arguments: [
        ("ポッキー極細 ¥199C", 199), ("ゼイタクギョウザ ¥349 E", 349), ("パン ¥1,200T", 1_200),
        ("ジュース ¥98x", 98), ("ガム 120*", 120), ("ガム ¥120 *", 120),
    ])
    func priceWithMark(line: String, yen: Int) {
        let result = items(line)
        #expect(result.map(\.priceYen) == [yen])
        let name = result.first?.name ?? ""
        #expect(!name.contains { "CETXx*¥".contains($0) }, "\(name)")
    }

    @Test func markIsNotPartOfTheName() {
        #expect(items("※01 ポッキー極細 ¥199C").map(\.name) == ["ポッキー極細"])
        #expect(items("MOカケルチーズ ¥399C").map(\.name) == ["MOカケルチーズ"])
    }

    /// Without ¥ a letter after the number is a unit or a code.
    @Test(arguments: ["ポテト 350g", "おにぎり 2P", "ボルト M8 10A"])
    func letterAfterBareNumberIsNotAPrice(line: String) {
        #expect(items(line).isEmpty)
    }

    @Test(arguments: [
        ("※01 テンネンスイ ¥170", "テンネンスイ"), ("90 サンショクダンゴ ¥278", "サンショクダンゴ"),
        ("※91 ゼイタクギョウザ ¥349C", "ゼイタクギョウザ"),
        ("7UP ¥150", "7UP"), ("3個入り プリン ¥198", "3個入りプリン"), ("1 リンゴ ¥120", "1 リンゴ"),
    ])
    func departmentCode(line: String, name: String) {
        #expect(items(line).map(\.name) == [name])
    }

    @Test func seiyuReceipt() {
        let result = items("""
        担当:00566
        ※01 テンネンスイ
        ¥85 x 2 ¥170C
        ※01 ファンタ グレープ
        ¥75 x 2 ¥150C
        ※01 ポッキー極細 ¥199C
        ※90 サンショクダンゴ
        ¥139 x 2 ¥278C
        ※91 ゼイタクギョウザ ¥349C
        ※90 MOカケルチーズ ¥399C
        小計 9点 ¥1,545
        """)
        #expect(result.map(\.priceYen) == [170, 150, 199, 278, 349, 399])
        #expect(result.allSatisfy { $0.isReducedRate })
        #expect(result.map(\.name).first == "テンネンスイ")
    }

    /// A name waiting for its quantity line is kept (price 0) when the next name arrives first.
    @Test func waitingNameIsKeptNotOverwritten() {
        let result = items("""
        牛乳 ¥198
        ※01 テンネンスイ
        ※01 ファンタ グレープ
        ¥75 x 2 ¥150
        """)
        #expect(result.map(\.priceYen) == [198, 0, 150])
        #expect(result[1].name == "テンネンスイ")
        #expect(result[1].isReducedRate)
    }

    /// Above the first item, a line without a price is the store's name, not an item.
    @Test func storeNameAboveItemsIsNotKept() {
        #expect(items("マツモトキヨシ\n新宿東口店\n化粧水 ¥1,320").map(\.name) == ["化粧水"])
    }
}

@Suite struct ReceiptParserItemTests {
    @Test func itemSumMakesTheTotalHighConfidence() {
        // No change line and no external tax: only the item sum can confirm the total.
        let draft = ReceiptParser.parse(text: """
        マツモトキヨシ
        化粧水 ¥1,320
        のど飴 ※ ¥216
        合計 ¥1,536
        クレジット ¥1,536
        """, today: .now)
        #expect(draft.items.map(\.priceYen) == [1_320, 216])
        #expect(draft.confidence(for: .totalYen) == .high)
        #expect(draft.confidence(for: .items) == .high)
    }

    /// B-13: the review screen asks the user to check items that do not add up.
    @Test func itemsThatDoNotAddUpAreLow() {
        let draft = ReceiptParser.parse(text: "化粧水 ¥1,320\n合計 ¥1,536", today: .now)
        #expect(draft.confidence(for: .totalYen) == .medium)
        #expect(draft.confidence(for: .items) == .low)
    }

    /// Tax added on top (外税): the items add up to the subtotal, not the total.
    @Test func seiyuItemsMatchTheSubtotal() {
        let draft = ReceiptParser.parse(text: """
        SEIYU
        ※01 ポッキー極細 ¥199C
        ※91 ゼイタクギョウザ ¥349C
        小計 2点 ¥548
        消費税額
        8% 2点 ¥43
        合計 ¥591
        """, today: .now)
        #expect(draft.items.map(\.priceYen) == [199, 349])
        #expect(draft.totalYen == 591)
        #expect(draft.tax8Yen == 43)
        #expect(draft.confidence(for: .items) == .high)
    }

    @Test func unpricedItemIsLow() {
        let draft = ReceiptParser.parse(text: "牛乳 ¥198\n※01 テンネンスイ\nパン ¥100\n合計 ¥298", today: .now)
        #expect(draft.items.map(\.priceYen) == [198, 0, 100])
        #expect(draft.confidence(for: .items) == .low)
    }
}
