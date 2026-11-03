import Testing
import KakeiboCore

@Suite struct YenTests {
    @Test(arguments: [
        (0, "¥0"),
        (5, "¥5"),
        (999, "¥999"),
        (1_000, "¥1,000"),
        (1_234, "¥1,234"),
        (12_345, "¥12,345"),
        (123_456, "¥123,456"),
        (1_234_567, "¥1,234,567"),
    ])
    func formatsPositiveAmounts(amount: Int, expected: String) {
        #expect(Yen.format(amount) == expected)
    }

    @Test(arguments: [
        (-1, "-¥1"),
        (-120, "-¥120"),
        (-1_000, "-¥1,000"),
        (-98_765, "-¥98,765"),
    ])
    func formatsDiscountsAsNegative(amount: Int, expected: String) {
        #expect(Yen.format(amount) == expected)
    }

    @Test func handlesIntExtremes() {
        #expect(Yen.format(Int.max) == "¥9,223,372,036,854,775,807")
        #expect(Yen.format(Int.min) == "-¥9,223,372,036,854,775,808")
    }
}
