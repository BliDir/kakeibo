import Testing
import KakeiboCore

@Suite struct TextNormalizerTests {
    private func n(_ line: String) -> String { TextNormalizer.normalizeLine(line) }

    // MARK: NFKC

    @Test(arguments: [
        ("１２３４", "1234"),
        ("ＴＯＴＡＬ", "TOTAL"),
        ("合計　￥１，０００", "合計 ¥1,000"),
        ("（税込）", "(税込)"),
        ("ｺｰﾋｰ", "コーヒー"),
        ("ﾎﾟｲﾝﾄ", "ポイント"),
        ("㈱ローソン", "(株)ローソン"),
    ])
    func appliesNFKC(input: String, expected: String) {
        #expect(n(input) == expected)
    }

    // MARK: Yen sign

    @Test(arguments: [
        (#"合計 \1,280"#, "合計 ¥1,280"),
        ("合計 ￥1,280", "合計 ¥1,280"),
        ("合計 ¥1,280", "合計 ¥1,280"),
        (#"\\500"#, "¥¥500"),
    ])
    func unifiesYenSign(input: String, expected: String) {
        #expect(n(input) == expected)
    }

    // MARK: Spaces

    @Test(arguments: [
        ("合 計", "合計"),
        ("お 預 り", "お預り"),
        ("お 釣 り ¥220", "お釣り ¥220"),
        ("セブン イレブン", "セブンイレブン"),
        ("光熱 ・ 通信", "光熱・通信"),
        ("小　計", "小計"),
    ])
    func removesSpacesBetweenJapanese(input: String, expected: String) {
        #expect(n(input) == expected)
    }

    @Test(arguments: [
        ("おにぎり 160", "おにぎり 160"),
        ("Coffee ラテ", "Coffee ラテ"),
        ("TOTAL 1,000", "TOTAL 1,000"),
    ])
    func keepsSpacesNextToLatinAndDigits(input: String, expected: String) {
        #expect(n(input) == expected)
    }

    @Test(arguments: [
        ("1, 000", "1,000"),
        ("1 ,000", "1,000"),
        ("12 , 345", "12,345"),
        ("1, 234, 567", "1,234,567"),
        ("¥ 500", "¥500"),
        (#"合計 \ 1, 280"#, "合計 ¥1,280"),
    ])
    func removesSpacesInsideNumbers(input: String, expected: String) {
        #expect(n(input) == expected)
    }

    @Test func doesNotMergeSeparateNumbers() {
        #expect(n("1,000, 2") == "1,000, 2")
        #expect(n("2 300") == "2 300")
    }

    @Test func collapsesAndTrimsWhitespace() {
        #expect(n("  TOTAL\t\t1,000  ") == "TOTAL 1,000")
    }

    // MARK: Letter O

    @Test(arguments: [
        ("1O0", "100"),
        ("1o5", "105"),
        ("1OO0", "1000"),
        ("¥1,O00", "¥1,000"),
        ("1O,000", "10,000"),
        ("2O26/11/03", "2026/11/03"),
        ("1, O76", "1,076"),
    ])
    func readsLetterOBetweenDigitsAsZero(input: String, expected: String) {
        #expect(n(input) == expected)
    }

    // Only between digits: a trailing O (`¥35O`) is left for the field parsers.
    @Test(arguments: ["No.123", "TOKYO 1", "1 ON", "10 off", "Oolong 100", "¥35O", "11/O3"])
    func leavesOtherLettersO(input: String) {
        #expect(n(input) == input)
    }

    // MARK: Lines

    @Test func keepsOrderAndDropsEmptyLines() {
        let lines = ["B", "", "  ", "　", "A", "C"]
        #expect(TextNormalizer.normalize(lines: lines) == ["B", "A", "C"])
    }

    @Test func splitsTextOnNewlines() {
        #expect(TextNormalizer.normalize(text: "合 計\r\n\n￥１００\n") == ["合計", "¥100"])
    }

    // MARK: Full receipt

    @Test func normalizesSampleReceipt() {
        let raw = """
        ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋 谷 店
        東京都渋谷区道玄坂１－２－３

        ２０２６年１１月　３日（火）　８：１５
        登録番号 Ｔ１２３４５６７８９０１２３
        おにぎり 鮭 ※ \\160
        ｺｰﾋｰ Ｌ \\2O0
        値 引 -30
        小 計 \\ 3O0
        (8%対象 \\1O0)
        合 計 \\1, O76
        お 預 り \\1, 1O0
        お 釣 り \\24
        """
        let expected = [
            "セブン-イレブン渋谷店",
            "東京都渋谷区道玄坂1-2-3",
            "2026年11月 3日(火) 8:15",
            "登録番号 T1234567890123",
            "おにぎり鮭 ※ ¥160",
            "コーヒー L ¥200",
            "値引 -30",
            "小計 ¥300",
            "(8%対象 ¥100)",
            "合計 ¥1,076",
            "お預り ¥1,100",
            "お釣り ¥24",
        ]
        #expect(TextNormalizer.normalize(text: raw) == expected)
    }
}
