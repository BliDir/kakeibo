import CoreGraphics
import Foundation
import Observation

/// One scan, from the captured image to a parsed draft, for the scanning screens.
///
/// Main-actor state the UI observes. `start` runs the pipeline in a task that `cancel`
/// stops; a cancelled or reset session keeps nothing (no image, no result).
@MainActor
@Observable
public final class ScanSession {
    public enum Source: Sendable, Equatable {
        /// The VisionKit document camera: already flattened and straightened.
        case camera
        /// A photo picked from the library.
        case photoLibrary
    }

    public enum Phase: Sendable, Equatable {
        case idle
        case processing(ExtractionStage)
        /// `result` holds the draft.
        case finished
        case failed(ExtractionError)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var source: Source?
    /// The upright image being read, for the preview and for saving with the expense.
    public private(set) var image: CGImage?
    /// The original encoded photo when it came from the library (saved with its metadata).
    public private(set) var imageData: Data?
    public private(set) var result: ExtractionResult?

    public let pipeline: ExtractionPipeline
    private var task: Task<Void, Never>?

    public init(pipeline: ExtractionPipeline) {
        self.pipeline = pipeline
    }

    /// Reads a captured page (from the document camera).
    public func start(image: CGImage, source: Source = .camera) {
        begin(source: source, image: image, data: nil)
    }

    /// Reads a photo from the library.
    ///
    /// The progress phase starts at once; the photo is decoded off the main thread (a 24 MP
    /// HEIC takes long enough to freeze the screen), then read. An undecodable photo fails
    /// with `.unreadableImage`.
    public func start(imageData: Data) {
        cancel()
        source = .photoLibrary
        self.imageData = imageData
        phase = .processing(.readingText)
        task = Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                ImageDecoding.uprightImage(from: imageData, maxPixelSize: KakeiboScan.maxOCRPixelSize)
            }.value
            guard !Task.isCancelled, let self else { return }
            guard let image else {
                self.imageData = nil
                phase = .failed(.unreadableImage)
                return
            }
            self.image = image
            await read(image)
        }
    }

    /// Stops reading and forgets the image and any result.
    public func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
        source = nil
        image = nil
        imageData = nil
        result = nil
    }

    /// Back to idle after the result has been handed on.
    public func reset() { cancel() }

    /// Waits until the current run has finished. For tests.
    public func waitUntilFinished() async {
        await task?.value
    }

    private func begin(source: Source, image: CGImage, data: Data?) {
        cancel()
        self.source = source
        self.image = image
        self.imageData = data
        phase = .processing(.readingText)
        task = Task { [weak self] in await self?.read(image) }
    }

    /// Runs the pipeline off the main actor, showing its stages, then the result.
    private func read(_ image: CGImage) async {
        let pipeline = self.pipeline
        let (stages, continuation) = AsyncStream.makeStream(of: ExtractionStage.self)
        let work = Task.detached { () async -> Result<ExtractionResult, ExtractionError> in
            defer { continuation.finish() }
            do throws(ExtractionError) {
                return .success(try await pipeline.extract(image, progress: { continuation.yield($0) }))
            } catch {
                return .failure(error)
            }
        }
        await withTaskCancellationHandler {
            for await stage in stages {
                guard !Task.isCancelled else { break }
                show(stage)
            }
            let outcome = await work.value
            guard !Task.isCancelled else { return }
            finish(outcome)
        } onCancel: {
            work.cancel()
        }
    }

    private func show(_ stage: ExtractionStage) {
        switch stage {
        case .readingText, .understandingReceipt: phase = .processing(stage)
        case .done, .failed: break   // `finish` sets the final phase with the result
        }
    }

    private func finish(_ outcome: Result<ExtractionResult, ExtractionError>) {
        switch outcome {
        case .success(let value):
            result = value
            phase = .finished
        case .failure(.cancelled):
            cancel()
        case .failure(let error):
            phase = .failed(error)
        }
    }
}
