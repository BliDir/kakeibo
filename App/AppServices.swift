import Foundation
import KakeiboCore
import KakeiboScan
import KakeiboStore
import SwiftData

/// The app's long-lived services, made once at launch.
@MainActor
final class AppServices {
    let container: ModelContainer
    let photoStore: PhotoStore?
    let repository: ExpenseRepository
    let pipeline: ExtractionPipeline

    init(container: ModelContainer, photoStore: PhotoStore?, pipeline: ExtractionPipeline) {
        self.container = container
        self.photoStore = photoStore
        self.pipeline = pipeline
        repository = ExpenseRepository(container: container, photoStore: photoStore)
    }

    static func make() -> AppServices {
        let environment = ProcessInfo.processInfo.environment
        #if DEBUG
        // UI tests start from an empty ledger and leave nothing behind.
        if environment["KAKEIBO_IN_MEMORY_STORE"] == "1" {
            let photos = FileManager.default.temporaryDirectory.appendingPathComponent("UITestReceipts-\(UUID().uuidString)")
            let services = AppServices(
                container: try! KakeiboStore.makeContainer(inMemory: true),
                photoStore: try? PhotoStore(directory: photos),
                pipeline: makePipeline(environment)
            )
            if environment["KAKEIBO_SEED_SAMPLE"] == "1" { services.seedSample() }
            return services
        }
        #endif
        do {
            return AppServices(
                container: try KakeiboStore.makeContainer(),
                photoStore: try? PhotoStore.appDefault(),
                pipeline: makePipeline(environment)
            )
        } catch {
            // A store that cannot open is unrecoverable for a ledger app.
            fatalError("Could not open the expense store: \(error)")
        }
    }

    #if DEBUG
    /// Made-up expenses for UI tests and screenshots: four this month, one last month.
    private func seedSample() {
        let thisMonth = LedgerMonth(containing: .now)
        func day(_ month: LedgerMonth, _ d: Int) -> String { month.key + String(format: "-%02d", d) }
        let today = Int(DayKey.make(from: .now).suffix(2))!
        let samples: [(String, String, String?, Int, Int?, Int?, PaymentMethod, ExpenseCategory, Int)] = [
            (day(thisMonth, today), "まいばすけっと 架空町店", "My Basket", 1_310, 29, 72, .icCard, .groceries, 5),
            (day(thisMonth, today), "スターバックス", "Starbucks", 1_078, 98, nil, .credit, .dining, 0),
            (day(thisMonth, max(1, today - 1)), "JR東日本", nil, 2_150, nil, nil, .icCard, .transport, 0),
            (day(thisMonth, max(1, today - 1)), "ダイソー", "Daiso", 660, 60, nil, .cash, .household, 2),
            (day(thisMonth.previous, 28), "西松屋", "Nishimatsuya", 3_278, 298, nil, .qrPay, .kids, 4),
        ]
        for (dayKey, store, english, total, tax10, tax8, payment, category, items) in samples {
            let draft = ReceiptDraft(
                storeName: store, storeNameEn: english, dayKey: dayKey, totalYen: total, tax10Yen: tax10, tax8Yen: tax8,
                payment: payment, category: category,
                items: (0..<items).map { LineItemDraft(name: "品目\($0 + 1)", priceYen: total / max(items, 1)) }
            )
            _ = try? repository.create(from: draft, source: .manual)
        }
    }
    #endif

    /// Deletes receipt photos no expense refers to (for example from a crash mid-save).
    func cleanUp() {
        _ = try? repository.removeOrphanPhotos()
    }

    private static func makePipeline(_ environment: [String: String]) -> ExtractionPipeline {
        #if DEBUG
        // UI tests slow OCR down so the progress screen stays up long enough to check and cancel,
        // and turn the on-device model off so results do not depend on the machine.
        let refiner: any ReceiptRefiner = environment["KAKEIBO_NO_REFINER"] == "1" ? NoopRefiner() : ReceiptRefiners.automatic()
        if let text = environment["KAKEIBO_SCAN_OCR_DELAY"], let seconds = Double(text) {
            return ExtractionPipeline(ocr: DelayedOCR(base: VisionOCRService(), delay: .seconds(seconds)), refiner: refiner)
        }
        return ExtractionPipeline(refiner: refiner)
        #else
        return ExtractionPipeline()
        #endif
    }
}

#if DEBUG
import CoreGraphics
import KakeiboCore

/// Waits before reading, for UI tests only.
private struct DelayedOCR: OCRService {
    let base: any OCRService
    let delay: Duration

    func recognize(_ image: CGImage) async throws -> [TextObservation] {
        try await Task.sleep(for: delay)
        return try await base.recognize(image)
    }
}
#endif
