import Foundation
import KakeiboCore

/// Improves a parser draft after OCR. Never throws: on any problem it returns the draft unchanged.
public protocol ReceiptRefiner: Sendable {
    func refine(lines: [String], draft: ReceiptDraft) async -> ReceiptDraft
}

/// Used when no on-device model is available: returns the parser draft as is.
public struct NoopRefiner: ReceiptRefiner {
    public init() {}
    public func refine(lines: [String], draft: ReceiptDraft) async -> ReceiptDraft { draft }
}

/// What a language model read from the receipt. Plain values, so merge rules are testable
/// without Foundation Models.
public struct ModelReceipt: Sendable, Equatable {
    public var storeName: String?
    /// `yyyy-MM-dd`.
    public var dayKey: String?
    public var totalYen: Int?
    public var tax10Yen: Int?
    public var tax8Yen: Int?
    public var payment: PaymentMethod?
    public var items: [LineItemDraft]

    public init(storeName: String? = nil, dayKey: String? = nil, totalYen: Int? = nil, tax10Yen: Int? = nil,
                tax8Yen: Int? = nil, payment: PaymentMethod? = nil, items: [LineItemDraft] = []) {
        self.storeName = storeName
        self.dayKey = dayKey
        self.totalYen = totalYen
        self.tax10Yen = tax10Yen
        self.tax8Yen = tax8Yen
        self.payment = payment
        self.items = items
    }
}

/// A model that reads a receipt from a prompt.
public protocol ReceiptModel: Sendable {
    func read(prompt: String) async throws -> ModelReceipt
}

/// Runs a `ReceiptModel` within a time limit and merges its answer into the parser draft.
///
/// This holds everything except the model call, so tests drive it with a mock model.
public struct ModelRefiner: ReceiptRefiner {
    public let model: any ReceiptModel
    public let timeLimit: Duration

    /// The design doc's limit: after this, the parser draft is used unchanged.
    public static let defaultTimeLimit: Duration = .seconds(10)

    public init(model: any ReceiptModel, timeLimit: Duration = ModelRefiner.defaultTimeLimit) {
        self.model = model
        self.timeLimit = timeLimit
    }

    public func refine(lines: [String], draft: ReceiptDraft) async -> ReceiptDraft {
        let prompt = RefinerPrompt.make(lines: ModelLineSelector.select(lines), draft: draft)
        guard let answer = await Self.withTimeLimit(timeLimit, { try await model.read(prompt: prompt) }) else {
            return draft
        }
        return RefinementMerger.merge(draft: draft, model: answer)
    }

    /// The operation's result, or nil if it throws or does not finish in time.
    static func withTimeLimit<T: Sendable>(_ limit: Duration, _ operation: @escaping @Sendable () async throws -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { try? await operation() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

public enum ReceiptRefiners {
    /// The on-device model refiner when Apple Intelligence is available, otherwise `NoopRefiner`.
    public static func automatic() -> any ReceiptRefiner {
        select(isModelAvailable: FoundationModelsRefiner.isAvailable)
    }

    static func select(isModelAvailable: Bool) -> any ReceiptRefiner {
        isModelAvailable ? FoundationModelsRefiner() : NoopRefiner()
    }
}
