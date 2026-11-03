import Foundation
import Testing
import KakeiboCore

@Suite struct CategoryTests {
    @Test func hasNineCategoriesInOrder() {
        #expect(ExpenseCategory.allCases.map(\.rawValue) == [
            "groceries", "dining", "transport", "household", "kids",
            "health", "shopping", "utilities", "other",
        ])
    }

    @Test func japaneseNamesMatchDesign() {
        #expect(ExpenseCategory.allCases.map(\.japaneseName) == [
            "食料品", "外食", "交通", "日用品", "子ども", "医療", "買い物", "光熱・通信", "その他",
        ])
    }

    @Test func displayNameFollowsLanguage() {
        #expect(ExpenseCategory.utilities.displayName(for: .ja) == "光熱・通信")
        #expect(ExpenseCategory.utilities.displayName(for: .en) == "Utilities")
    }

    @Test func everyCategoryHasBothNames() {
        for category in ExpenseCategory.allCases {
            #expect(!category.japaneseName.isEmpty)
            #expect(!category.englishName.isEmpty)
        }
    }
}

@Suite struct EnumTests {
    @Test func paymentMethodRawValues() {
        #expect(PaymentMethod.allCases.map(\.rawValue) == ["cash", "credit", "icCard", "qrPay", "other"])
    }

    @Test func confidenceIsOrdered() {
        #expect(Confidence.low < .medium)
        #expect(Confidence.medium < .high)
        #expect(Confidence.allCases.max() == .high)
    }
}

@Suite struct ReceiptDraftTests {
    static let sample = ReceiptDraft(
        storeName: "セブン-イレブン 渋谷店",
        storeNameEn: "7-Eleven Shibuya",
        dayKey: "2026-11-03",
        time: "08:15",
        totalYen: 1_076,
        tax10Yen: 20,
        tax8Yen: 72,
        payment: .icCard,
        category: .groceries,
        invoiceNumber: "T1234567890123",
        items: [
            LineItemDraft(name: "おにぎり 鮭", nameEn: "Rice ball, salmon", priceYen: 160, isReducedRate: true),
            LineItemDraft(name: "コーヒー", priceYen: 220),
            LineItemDraft(name: "値引", priceYen: -30, isReducedRate: true),
        ],
        confidences: [.totalYen: .high, .dayKey: .medium]
    )

    @Test func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(Self.sample)
        let decoded = try JSONDecoder().decode(ReceiptDraft.self, from: data)
        #expect(decoded == Self.sample)
    }

    @Test func emptyDraftRoundTrip() throws {
        let empty = ReceiptDraft()
        let data = try JSONEncoder().encode(empty)
        #expect(try JSONDecoder().decode(ReceiptDraft.self, from: data) == empty)
    }

    @Test func encodesStableKeysAndRawValues() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = try #require(String(data: encoder.encode(Self.sample), encoding: .utf8))
        #expect(json.contains(#""payment":"icCard""#))
        #expect(json.contains(#""category":"groceries""#))
        // Confidences encode as a JSON object keyed by field name, not as an array.
        #expect(json.contains(#""confidences":{"dayKey":"medium","totalYen":"high"}"#))
    }

    @Test func missingConfidenceIsLow() {
        #expect(Self.sample.confidence(for: .totalYen) == .high)
        #expect(Self.sample.confidence(for: .storeName) == .low)
    }
}

@Suite struct LineItemDraftTests {
    @Test func codableRoundTrip() throws {
        let item = LineItemDraft(name: "牛乳", nameEn: "Milk", priceYen: 198, isReducedRate: true)
        let data = try JSONEncoder().encode(item)
        #expect(try JSONDecoder().decode(LineItemDraft.self, from: data) == item)
    }

    @Test func defaultsToStandardRate() {
        #expect(LineItemDraft(name: "電池", priceYen: 400).isReducedRate == false)
    }
}

@Suite struct EnumCodableTests {
    @Test func everyEnumRoundTrips() throws {
        try roundTrip(ExpenseCategory.allCases)
        try roundTrip(PaymentMethod.allCases)
        try roundTrip(Confidence.allCases)
        try roundTrip(ReceiptField.allCases)
        try roundTrip(AppLanguage.allCases)
    }

    private func roundTrip<T: Codable & Equatable>(_ values: [T]) throws {
        let data = try JSONEncoder().encode(values)
        #expect(try JSONDecoder().decode([T].self, from: data) == values)
    }
}

@Suite struct ExpenseSourceTests {
    @Test func rawValuesAreStable() throws {
        #expect(ExpenseSource.allCases.map(\.rawValue) == ["scan", "manual"])
        let data = try JSONEncoder().encode(ExpenseSource.allCases)
        #expect(try JSONDecoder().decode([ExpenseSource].self, from: data) == ExpenseSource.allCases)
    }
}
