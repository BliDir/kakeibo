import KakeiboCore
import KakeiboScan
import SwiftUI

/// Placeholder ledger with the scan entry. T-40 replaces the ledger part.
struct ContentView: View {
    @State private var session = ScanSession(pipeline: Self.makePipeline())

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "ledger.empty.title",
                systemImage: "doc.text.viewfinder",
                description: Text("ledger.empty.message")
            )
            .navigationTitle("app.title")
            .safeAreaInset(edge: .bottom) {
                ScanEntryButtons(session: session)
                    .padding(.bottom, 16)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { session.phase != .idle },
            set: { if !$0 { session.cancel() } }
        )) {
            ScanFlowView(session: session)
        }
        #if DEBUG
        .task { startDebugScanIfRequested() }
        #endif
    }

    private static func makePipeline() -> ExtractionPipeline {
        #if DEBUG
        // UI tests slow OCR down so the progress screen stays up long enough to check and cancel.
        if let text = ProcessInfo.processInfo.environment["KAKEIBO_SCAN_OCR_DELAY"], let seconds = Double(text) {
            return ExtractionPipeline(ocr: DelayedOCR(base: VisionOCRService(), delay: .seconds(seconds)))
        }
        #endif
        return ExtractionPipeline()
    }

    #if DEBUG
    /// UI tests pass a receipt image path, so the scan flow can run on the simulator
    /// without the photo picker. Same path as a library photo.
    private func startDebugScanIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["KAKEIBO_SCAN_IMAGE_PATH"],
              let data = FileManager.default.contents(atPath: path) else { return }
        session.start(imageData: data)
    }
    #endif
}

#Preview {
    ContentView()
}

#if DEBUG
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
