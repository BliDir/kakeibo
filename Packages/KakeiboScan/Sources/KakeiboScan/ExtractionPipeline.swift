import CoreGraphics
import Foundation
import KakeiboCore

/// Turns a receipt image into a `ReceiptDraft`, all on the device.
///
/// Two steps, so the user never waits for the language model:
/// 1. `extract(_:)`: OCR → lines → `ReceiptParser`. Takes about a second; the review screen
///    shows its draft straight away.
/// 2. `refine(_:)`: the on-device model (when available) improves the draft. Call it in the
///    background after showing the review screen, and apply the answer with
///    `BackgroundRefinement.apply` so fields the user already edited are kept.
public struct ExtractionPipeline: Sendable {
    public let ocr: any OCRService
    public let refiner: any ReceiptRefiner
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - ocr: defaults to Vision.
    ///   - refiner: defaults to the on-device model when available, otherwise no refinement.
    ///   - now: the scan date, used for month-day dates. Injected for tests.
    public init(
        ocr: any OCRService = VisionOCRService(),
        refiner: any ReceiptRefiner = ReceiptRefiners.automatic(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.ocr = ocr
        self.refiner = refiner
        self.now = now
    }

    /// True when `refine(_:)` can change the draft, so the UI can show "improving…".
    public var canRefine: Bool { !(refiner is NoopRefiner) }

    // MARK: - Extract

    /// Reads the image and parses it.
    ///
    /// Reports `.readingText`, `.understandingReceipt`, then `.done` or `.failed`.
    /// Has no side effects, so cancelling the calling task leaves nothing behind;
    /// it then throws `.cancelled`.
    public func extract(
        _ image: CGImage,
        progress: @Sendable (ExtractionStage) -> Void = { _ in }
    ) async throws(ExtractionError) -> ExtractionResult {
        do {
            let result = try await run(image, progress: progress)
            progress(.done)
            return result
        } catch {
            progress(.failed(error))
            throw error
        }
    }

    /// Decodes image data (JPEG, HEIC, PNG from the photo library) upright and extracts it.
    public func extract(
        imageData: Data,
        progress: @Sendable (ExtractionStage) -> Void = { _ in }
    ) async throws(ExtractionError) -> ExtractionResult {
        guard let image = ImageDecoding.uprightImage(from: imageData, maxPixelSize: KakeiboScan.maxOCRPixelSize) else {
            progress(.failed(.unreadableImage))
            throw .unreadableImage
        }
        return try await extract(image, progress: progress)
    }

    /// Smallest side, in pixels, worth sending to OCR.
    static let minimumPixelSize = 32

    private func run(_ image: CGImage, progress: (ExtractionStage) -> Void) async throws(ExtractionError) -> ExtractionResult {
        guard min(image.width, image.height) >= Self.minimumPixelSize else { throw .unreadableImage }
        let clock = ContinuousClock()

        progress(.readingText)
        try Self.checkCancellation()
        let ocrStart = clock.now
        let observations: [TextObservation]
        do {
            observations = try await ocr.recognize(image)
        } catch {
            if Task.isCancelled || error is CancellationError { throw .cancelled }
            throw .unreadableImage
        }
        let ocrTime = clock.now - ocrStart

        progress(.understandingReceipt)
        try Self.checkCancellation()
        let parseStart = clock.now
        let lines = LineBuilder.lines(from: observations)
        guard !lines.isEmpty else { throw .noTextFound }
        let draft = ReceiptParser.parse(lines: lines, today: now())
        let parseTime = clock.now - parseStart
        try Self.checkCancellation()

        return ExtractionResult(
            draft: draft,
            lines: lines,
            timings: ExtractionTimings(ocr: ocrTime, parse: parseTime)
        )
    }

    private static func checkCancellation() throws(ExtractionError) {
        if Task.isCancelled { throw .cancelled }
    }

    // MARK: - Refine

    /// The refined draft, or `result.draft` unchanged when there is no model, it fails,
    /// or it runs out of time. Call it in the background; it can take tens of seconds.
    public func refine(_ result: ExtractionResult) async -> ReceiptDraft {
        await refiner.refine(lines: result.lines, draft: result.draft)
    }
}

/// What `extract` returns.
public struct ExtractionResult: Sendable, Equatable {
    /// The parser's draft.
    public var draft: ReceiptDraft
    /// Receipt rows rebuilt from OCR, top to bottom.
    public var lines: [String]
    public var timings: ExtractionTimings

    /// The OCR text to keep with the expense (`Expense.ocrText`), one row per line.
    public var ocrText: String { lines.joined(separator: "\n") }
}

public struct ExtractionTimings: Sendable, Equatable {
    /// Downscaling and Vision OCR.
    public var ocr: Duration
    /// Line building and parsing.
    public var parse: Duration
}

/// Progress for the scanning UI.
public enum ExtractionStage: Sendable, Equatable {
    /// 文字を読み取り中 / Reading text
    case readingText
    /// レシートを解析中 / Understanding receipt
    case understandingReceipt
    case done
    case failed(ExtractionError)
}

/// What can go wrong, as the user should hear it.
public enum ExtractionError: Error, Sendable, Equatable {
    /// The image could not be decoded or read (too small, corrupt, OCR error).
    case unreadableImage
    /// The image was read but contains no text: probably not a receipt, or too blurry.
    case noTextFound
    /// The task was cancelled; nothing was kept.
    case cancelled
}
