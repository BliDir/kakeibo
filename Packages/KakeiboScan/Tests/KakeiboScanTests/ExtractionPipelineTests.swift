import CoreGraphics
import Foundation
import KakeiboCore
import Testing
@testable import KakeiboScan

/// OCR that returns fixed observations, optionally slowly, or fails.
struct MockOCR: OCRService {
    var observations: [TextObservation] = []
    var delay: Duration = .zero
    var error: (any Error)?

    func recognize(_ image: CGImage) async throws -> [TextObservation] {
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return observations
    }
}

/// Collects progress stages from any thread.
final class StageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _stages: [ExtractionStage] = []
    var stages: [ExtractionStage] { lock.withLock { _stages } }
    func record(_ stage: ExtractionStage) { lock.withLock { _stages.append(stage) } }
}

/// A refiner that records it was called and returns a fixed change.
struct StubRefiner: ReceiptRefiner {
    var change: @Sendable (ReceiptDraft) -> ReceiptDraft
    func refine(lines: [String], draft: ReceiptDraft) async -> ReceiptDraft { change(draft) }
}

private let scanDay = Date(timeIntervalSince1970: 1_793_674_800) // 2026-11-03 12:00 Tokyo

private func row(_ text: String, x: Double, y: Double) -> TextObservation {
    TextObservation(text: text, boundingBox: BoundingBox(x: x, y: y, width: 0.25, height: 0.03), confidence: 0.9)
}

private let receiptRows = [
    row("サンプルマート", x: 0.05, y: 0.05),
    row("2026/11/03 18:42", x: 0.05, y: 0.10),
    row("合計", x: 0.05, y: 0.50), row("¥754", x: 0.65, y: 0.50),
    row("お預り", x: 0.05, y: 0.55), row("¥1,000", x: 0.65, y: 0.55),
    row("お釣り", x: 0.05, y: 0.60), row("¥246", x: 0.65, y: 0.60),
]

@Suite struct ExtractionPipelineTests {
    let image = ScanTestImages.solid(width: 600, height: 900)

    private func pipeline(_ ocr: MockOCR, refiner: any ReceiptRefiner = NoopRefiner()) -> ExtractionPipeline {
        ExtractionPipeline(ocr: ocr, refiner: refiner, now: { scanDay })
    }

    @Test func extractsDraftAndOCRText() async throws {
        let recorder = StageRecorder()
        let result = try await pipeline(MockOCR(observations: receiptRows)).extract(image, progress: recorder.record)

        #expect(result.draft.totalYen == 754)
        #expect(result.draft.confidence(for: .totalYen) == .high)
        #expect(result.draft.dayKey == "2026-11-03")
        #expect(result.lines == ["サンプルマート", "2026/11/03 18:42", "合計 ¥754", "お預り ¥1,000", "お釣り ¥246"])
        #expect(result.ocrText == result.lines.joined(separator: "\n"))
        #expect(recorder.stages == [.readingText, .understandingReceipt, .done])
    }

    @Test func extractDoesNotWaitForRefiner() async throws {
        let refiner = StubRefiner { var d = $0; d.storeNameEn = "Refined"; return d }
        let result = try await pipeline(MockOCR(observations: receiptRows), refiner: refiner).extract(image)
        #expect(result.draft.storeNameEn == nil)
    }

    @Test func refineRunsTheRefiner() async throws {
        let refiner = StubRefiner { var d = $0; d.items = [LineItemDraft(name: "牛乳", nameEn: "Milk", priceYen: 198)]; return d }
        let p = pipeline(MockOCR(observations: receiptRows), refiner: refiner)
        let result = try await p.extract(image)
        let refined = await p.refine(result)
        #expect(refined.items.first?.nameEn == "Milk")
        #expect(refined.totalYen == result.draft.totalYen)
        #expect(p.canRefine)
        #expect(!pipeline(MockOCR()).canRefine)
    }

    @Test func noTextFound() async {
        let recorder = StageRecorder()
        await #expect(throws: ExtractionError.noTextFound) {
            try await pipeline(MockOCR(observations: [])).extract(image, progress: recorder.record)
        }
        #expect(recorder.stages == [.readingText, .understandingReceipt, .failed(.noTextFound)])
    }

    @Test func ocrErrorIsUnreadableImage() async {
        struct VisionFailed: Error {}
        let recorder = StageRecorder()
        await #expect(throws: ExtractionError.unreadableImage) {
            try await pipeline(MockOCR(error: VisionFailed())).extract(image, progress: recorder.record)
        }
        #expect(recorder.stages == [.readingText, .failed(.unreadableImage)])
    }

    @Test func tinyImageIsUnreadable() async {
        await #expect(throws: ExtractionError.unreadableImage) {
            try await pipeline(MockOCR(observations: receiptRows)).extract(ScanTestImages.solid(width: 10, height: 10))
        }
    }

    @Test func undecodableDataIsUnreadable() async {
        let recorder = StageRecorder()
        await #expect(throws: ExtractionError.unreadableImage) {
            try await pipeline(MockOCR()).extract(imageData: Data("not an image".utf8), progress: recorder.record)
        }
        #expect(recorder.stages == [.failed(.unreadableImage)])
    }

    @Test func cancellingStopsWithoutAResult() async {
        let recorder = StageRecorder()
        let p = pipeline(MockOCR(observations: receiptRows, delay: .seconds(10)))
        let image = self.image
        let task = Task { try await p.extract(image, progress: recorder.record) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()

        let start = ContinuousClock.now
        let outcome = await task.result
        #expect(ContinuousClock.now - start < .seconds(2))
        switch outcome {
        case .success: Issue.record("cancelled extraction returned a result")
        case .failure(let error): #expect(error as? ExtractionError == .cancelled)
        }
        #expect(!recorder.stages.contains(.done))
        #expect(recorder.stages.last == .failed(.cancelled))
    }
}

/// Integration: real Vision OCR on the bundled made-up receipts, on the simulator and on macOS.
@Suite struct ExtractionPipelineIntegrationTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var image: String
        var total: Int
        var dayKey: String
        var payment: PaymentMethod
        var tax10: Int?
        var tax8: Int?
        /// Item prices to expect, when checked.
        var items: [Int]? = nil
        var testDescription: String { image }
    }

    static let cases = [
        Case(image: "sample-receipt", total: 754, dayKey: "2026-11-03", payment: .cash, tax10: 67, tax8: nil),
        Case(image: "konbini-receipt", total: 378, dayKey: "2026-11-02", payment: .icCard, tax10: nil, tax8: 28),
        Case(image: "supermarket-skewed-receipt", total: 841, dayKey: "2026-10-28", payment: .credit, tax10: 32, tax8: 35),
        // B-15: tight rows photographed 4° crooked; the price column drifts about a row.
        Case(image: "familymart-tilted-receipt", total: 1_469, dayKey: "2026-11-07", payment: .credit, tax10: 0, tax8: 108,
             items: [170, 150, 210, 236, 5, 498, 200]),
    ]

    @Test(arguments: cases)
    func extractsBundledReceipt(_ expected: Case) async throws {
        let p = ExtractionPipeline(ocr: VisionOCRService(), refiner: NoopRefiner(), now: { scanDay })
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await p.extract(imageData: try ScanTestImages.bundledData(expected.image))
        let total = clock.now - start

        print("""
        [\(expected.image)] OCR \(result.timings.ocr), parse \(result.timings.parse), total \(total)
        \(result.ocrText)
        """)

        #expect(result.draft.totalYen == expected.total)
        #expect(result.draft.dayKey == expected.dayKey)
        #expect(result.draft.payment == expected.payment)
        #expect(result.draft.tax10Yen == expected.tax10)
        #expect(result.draft.tax8Yen == expected.tax8)
        if let items = expected.items {
            #expect(result.draft.items.map(\.priceYen) == items)
            #expect(result.draft.confidence(for: .items) == .high)
        }
        #expect(result.lines.contains { $0.hasPrefix("合計") && $0.filter(\.isNumber).contains("\(expected.total)") },
                "合計 and its amount should be on one rebuilt line")
    }
}
