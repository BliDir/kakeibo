import Foundation
import FoundationModels
import KakeiboCore

/// Refines receipts with Apple's on-device model (Apple Intelligence iPhones only).
/// Free, offline, and nothing leaves the phone.
public struct FoundationModelsRefiner: ReceiptRefiner {
    private let refiner: ModelRefiner

    public init(timeLimit: Duration = ModelRefiner.defaultTimeLimit) {
        refiner = ModelRefiner(model: FoundationModelsReceiptModel(), timeLimit: timeLimit)
    }

    /// True when the system model can be used right now.
    public static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func refine(lines: [String], draft: ReceiptDraft) async -> ReceiptDraft {
        guard Self.isAvailable else { return draft }
        return await refiner.refine(lines: lines, draft: draft)
    }
}

/// Calls `LanguageModelSession` with guided generation.
struct FoundationModelsReceiptModel: ReceiptModel {
    func read(prompt: String) async throws -> ModelReceipt {
        let session = LanguageModelSession(instructions: RefinerPrompt.instructions)
        let response = try await session.respond(
            to: prompt,
            generating: GeneratedReceipt.self,
            options: GenerationOptions(sampling: .greedy)
        )
        return response.content.modelReceipt
    }
}

@Generable
struct GeneratedReceipt {
    @Guide(description: "Store name as printed on the receipt")
    var storeName: String?

    @Guide(description: "Purchase date as yyyy-MM-dd")
    var date: String?

    @Guide(description: "Total amount paid in yen (合計)")
    var totalYen: Int?

    @Guide(description: "Consumption tax at 10% in yen")
    var tax10Yen: Int?

    @Guide(description: "Consumption tax at the reduced 8% rate in yen")
    var tax8Yen: Int?

    @Guide(description: "How the receipt was paid")
    var payment: GeneratedPayment?

    @Guide(description: "Every item line, in receipt order")
    var items: [GeneratedItem]

    var modelReceipt: ModelReceipt {
        ModelReceipt(
            storeName: storeName,
            dayKey: date,
            totalYen: totalYen,
            tax10Yen: tax10Yen,
            tax8Yen: tax8Yen,
            payment: payment?.paymentMethod,
            items: items.map {
                LineItemDraft(name: $0.name, nameEn: $0.nameEn, priceYen: $0.priceYen, isReducedRate: $0.isReducedRate)
            }
        )
    }
}

@Generable
struct GeneratedItem {
    @Guide(description: "Item name as printed, in Japanese")
    var name: String

    @Guide(description: "Short natural English name for the item")
    var nameEn: String?

    @Guide(description: "Price in yen; negative for discounts (値引)")
    var priceYen: Int

    @Guide(description: "True when the item is marked ※ or ★ (8% reduced rate)")
    var isReducedRate: Bool
}

@Generable
enum GeneratedPayment {
    case cash, credit, icCard, qrPay, other

    var paymentMethod: PaymentMethod {
        switch self {
        case .cash: .cash
        case .credit: .credit
        case .icCard: .icCard
        case .qrPay: .qrPay
        case .other: .other
        }
    }
}
