import Foundation
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
            return AppServices(
                container: try! KakeiboStore.makeContainer(inMemory: true),
                photoStore: try? PhotoStore(directory: photos),
                pipeline: makePipeline(environment)
            )
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
