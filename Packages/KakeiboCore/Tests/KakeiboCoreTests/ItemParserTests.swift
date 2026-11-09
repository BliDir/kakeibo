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

    /// B-14, 7-Eleven: one subtotal per rate and none for the whole receipt.
    @Test func itemsMatchThePerRateSubtotals() {
        let draft = ReceiptParser.parse(text: """
        セブン-イレブン
        手巻おにぎり辛子明太子 *130
        メビウスワン 490込
        小 計(税抜 8%) ¥130
        消費税等( 8%) ¥10
        小 計(税込10%) ¥490
        合 計 ¥630
        """, today: .now)
        #expect(draft.items.map(\.priceYen) == [130, 490])
        #expect(draft.totalYen == 630)
        #expect(draft.confidence(for: .items) == .high)
    }

    @Test func unpricedItemIsLow() {
        let draft = ReceiptParser.parse(text: "牛乳 ¥198\n※01 テンネンスイ\nパン ¥100\n合計 ¥298", today: .now)
        #expect(draft.items.map(\.priceYen) == [198, 0, 100])
        #expect(draft.confidence(for: .items) == .low)
    }
}

/// B-14: layouts from real chain receipts.
@Suite struct ItemParserChainLayoutTests {
    private func items(_ text: String) -> [LineItemDraft] {
        ItemParser.parse(lines: TextNormalizer.normalize(text: text))
    }

    /// 7-Eleven: `*` right before the price marks 8%.
    @Test(arguments: ["手巻おにぎり辛子明太子 *130", "手巻おにぎり辛子明太子 * 130", "手巻おにぎり辛子明太子 *¥130"])
    func sevenElevenStar(line: String) {
        let result = items(line)
        #expect(result.map(\.priceYen) == [130])
        #expect(result.map(\.name) == ["手巻おにぎり辛子明太子"])
        #expect(result.first?.isReducedRate == true)
    }

    @Test func starAsMultiplierIsStillAQuantity() {
        let result = items("牛乳\n2*158")
        #expect(result.map(\.priceYen) == [316])
        #expect(result.first?.isReducedRate == false)
    }

    /// 7-Eleven `490込`, non-taxable `50非`, AEON `▽`: marks, not names.
    @Test(arguments: [
        ("メビウスワン 490込", "メビウスワン", 490), ("切手 50非", "切手", 50),
        ("ティッシュ 328外", "ティッシュ", 328), ("お茶 150内", "お茶", 150), ("パン 198▽", "パン", 198),
        ("▽パン 198", "パン", 198),
    ])
    func trailingTaxMarks(line: String, name: String, yen: Int) {
        let result = items(line)
        #expect(result.map(\.name) == [name])
        #expect(result.map(\.priceYen) == [yen])
    }

    /// AEON `(7個×単98)` and Life `2コX単1080 ¥2,160`.
    @Test func aeonQuantityUnderTheItem() {
        #expect(items("ヤクルト ※ 686\n(7個×単98)").map(\.priceYen) == [686])
        #expect(items("ヤクルト ※\n(7個×単98)").map(\.priceYen) == [686])
        #expect(items("お茶\n(2個 X 単58)").map(\.priceYen) == [116])
        #expect(items("お茶\n7個 × 単 98").map(\.priceYen) == [686])
    }

    @Test func lifeQuantityCompletesTheName() {
        let result = items("サインペン\n2コX単1080 ¥2,160\n超熟睡G420 10コ ¥428")
        #expect(result.map(\.name) == ["サインペン", "超熟睡G420 10コ"])
        #expect(result.map(\.priceYen) == [2_160, 428])
    }

    /// `1点※ ¥270` under a name gives that name its price, never an item called 1点.
    @Test func countLineCompletesTheName() {
        let result = items("焼きそばパン\n1点※ ¥270\nお茶 ¥150\nジャンボフランク\n2点 ¥396")
        #expect(result.map(\.name) == ["焼きそばパン", "お茶", "ジャンボフランク"])
        #expect(result.map(\.priceYen) == [270, 150, 396])
        #expect(result.map(\.isReducedRate) == [true, false, false])
    }

    @Test(arguments: [("半額 -199", -199), ("20%引 -60", -60), ("50円引 -50", -50), ("OFF -30", -30), ("ﾈﾋﾞｷ -20", -20)])
    func discountWords(line: String, yen: Int) {
        let result = items("お弁当 ※ ¥398\n\(line)")
        #expect(result.map(\.priceYen) == [398, yen])
        #expect(result.last?.isReducedRate == true, "a discount takes the rate of the item above")
    }

    @Test func coffeeIsNotADiscount() {
        #expect(items("COFFEE ¥300").map(\.priceYen) == [300])
    }

    /// FamilyMart: `◎` and other leading marks are not part of the name; `軽` right after the price.
    @Test func familyMartMarks() {
        let result = items("◎ミルクホイップクリー ¥235軽\n●おにぎり ¥120\n○パン ¥98\n◆お茶 ¥140\n☆ガム ¥110")
        #expect(result.map(\.name) == ["ミルクホイップクリー", "おにぎり", "パン", "お茶", "ガム"])
        #expect(result.first?.isReducedRate == true)
    }
}
