import Testing
import KakeiboCore

@Suite struct BackgroundRefinementTests {
    let original = ReceiptDraft(storeName: "サンプルマート", dayKey: "2026-11-03", totalYen: 754, payment: .cash,
                                category: .other,
                                confidences: [.storeName: .medium, .totalYen: .medium, .payment: .low, .category: .low])

    private var refined: ReceiptDraft {
        var r = original
        r.totalYen = 754
        r.confidences[.totalYen] = .low            // model disagreed
        r.payment = .credit
        r.confidences[.payment] = .medium
        r.tax10Yen = 68
        r.confidences[.tax10Yen] = .medium
        r.items = [LineItemDraft(name: "牛乳", nameEn: "Milk", priceYen: 198)]
        return r
    }

    @Test func untouchedFieldsTakeTheRefinement() {
        let applied = BackgroundRefinement.apply(refined: refined, original: original, current: original)
        #expect(applied == refined)
    }

    @Test func userEditsAreKept() {
        var current = original
        current.payment = .qrPay                 // the user picked PayPay
        current.confidences[.payment] = .high
        current.totalYen = 760                   // and corrected the total
        current.items = [LineItemDraft(name: "パン", priceYen: 150)]

        let applied = BackgroundRefinement.apply(refined: refined, original: original, current: current)
        #expect(applied.payment == .qrPay)
        #expect(applied.confidence(for: .payment) == .high)
        #expect(applied.totalYen == 760)
        #expect(applied.items.map(\.name) == ["パン"])
        // Fields the user did not touch still improve.
        #expect(applied.tax10Yen == 68)
        #expect(applied.confidence(for: .tax10Yen) == .medium)
    }

    @Test func unchangedValueTakesRefinedConfidence() {
        let applied = BackgroundRefinement.apply(refined: refined, original: original, current: original)
        #expect(applied.totalYen == 754)
        #expect(applied.confidence(for: .totalYen) == .low)
    }
}
