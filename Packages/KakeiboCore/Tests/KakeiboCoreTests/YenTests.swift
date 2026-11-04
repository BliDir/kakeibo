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

    @Test(arguments: [
        (1_234, "1,234円"),
        (0, "0円"),
        (5, "5円"),
        (-120, "-120円"),
        (1_234_567, "1,234,567円"),
    ])
    func formatsJapaneseWithEnSuffix(amount: Int, expected: String) {
        #expect(Yen.format(amount, for: .ja) == expected)
    }

    @Test func englishMatchesTheFixedFormat() {
        for amount in [0, 754, -120, 186_420] {
            #expect(Yen.format(amount, for: .en) == Yen.format(amount))
        }
    }

    @Test func fieldSymbolSide() {
        #expect(Yen.fieldSymbol(for: .en) == ("¥", true))
        #expect(Yen.fieldSymbol(for: .ja) == ("円", false))
    }

    @Test(arguments: [
        (1_234, AppLanguage.en, "1,234 yen"),
        (-120, AppLanguage.en, "minus 120 yen"),
        (0, AppLanguage.en, "0 yen"),
        (1_234, AppLanguage.ja, "1,234円"),
        (-120, AppLanguage.ja, "マイナス120円"),
    ])
    func spokenAmounts(amount: Int, language: AppLanguage, expected: String) {
        #expect(Yen.spoken(amount, for: language) == expected)
    }
}
