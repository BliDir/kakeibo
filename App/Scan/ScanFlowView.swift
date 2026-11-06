import KakeiboCore
import KakeiboScan
import KakeiboStore
import SwiftUI

/// Full-screen scan flow: progress, then an error or the review screen.
struct ScanFlowView: View {
    let session: ScanSession
    let services: AppServices
    let onSaved: (Int) -> Void
    /// The duplicate warning's "View saved entry": the scan is dropped and the saved expense opened.
    let onViewSaved: (Expense) -> Void
    /// The read error's "Enter manually": the scan is dropped and an empty manual form opens.
    let onManual: () -> Void

    var body: some View {
        ZStack {
            Theme.groundLight.ignoresSafeArea()
            switch session.phase {
            case .idle:
                EmptyView()
            case .processing(let stage):
                ScanProgressView(session: session, stage: stage)
            case .failed(let error):
                ScanErrorView(session: session, error: error, onManual: {
                    session.cancel()
                    onManual()
                }, close: session.cancel)
            case .finished:
                if let result = session.result {
                    ScanReviewHost(session: session, result: result, services: services,
                                   onSaved: onSaved, onViewSaved: onViewSaved)
                }
            }
        }
    }
}

/// The review screen for a finished scan. Refines the draft in the background while the
/// user checks it; leaving the screen cancels the refinement.
private struct ScanReviewHost: View {
    let session: ScanSession
    let result: ExtractionResult
    let services: AppServices
    let onSaved: (Int) -> Void
    let onViewSaved: (Expense) -> Void

    @State private var form: ReviewForm

    init(session: ScanSession, result: ExtractionResult, services: AppServices,
         onSaved: @escaping (Int) -> Void, onViewSaved: @escaping (Expense) -> Void) {
        self.session = session
        self.result = result
        self.services = services
        self.onSaved = onSaved
        self.onViewSaved = onViewSaved
        let photo: ReviewForm.PendingPhoto? = session.imageData.map { .data($0) } ?? session.image.map { .image($0) }
        _form = State(initialValue: ReviewForm(
            scan: result.draft, ocrText: result.ocrText, photo: photo, refining: services.pipeline.canRefine
        ))
    }

    var body: some View {
        ReviewView(form: form, services: services) { outcome in
            switch outcome {
            case .saved(let total):
                session.reset()
                onSaved(total)
            case .deleted, .discarded:
                session.cancel()
            case .viewSaved(let expense):
                onViewSaved(expense)
                session.cancel()
            }
        }
        .task {
            guard form.isRefining else { return }
            let refined = await services.pipeline.refine(result)
            guard !Task.isCancelled else { return }
            if refined != result.draft {
                form.applyRefinement(refined)
            } else {
                form.endRefinement()
            }
        }
    }
}

/// "Reading your receipt": the captured page and the pipeline's steps. Cancel stops the read
/// and returns to the ledger.
struct ScanProgressView: View {
    let session: ScanSession
    let stage: ExtractionStage
    @Environment(\.isAccessibilityTextSize) private var isAccessibilityTextSize

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("scan.progress.cancel", action: session.cancel)
                    .buttonStyle(TextButtonStyle())
                    .accessibilityIdentifier("scan.cancel")
                Spacer()
                // At the accessibility sizes it would wrap; the privacy line below says the same.
                if !isAccessibilityTextSize { Tag("scan.progress.onDevice") }
            }
            .padding(.top, Spacing.xs)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.source == .camera ? "scan.progress.eyebrow.camera" : "scan.progress.eyebrow.photo")
                            .eyebrow()
                        Text("scan.progress.title")
                            .font(.title.weight(.bold))
                            .foregroundStyle(Theme.text)
                            .accessibilityAddTraits(.isHeader)
                        Text("scan.progress.subtitle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    // Huge text: the steps need the room, so the preview goes.
                    if !isAccessibilityTextSize, let image = session.image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .padding(Spacing.s)
                            .frame(maxWidth: .infinity)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        if session.source == .camera {
                            StepRow(state: .done, title: "scan.step.captured.camera", detail: "scan.step.captured.camera.detail")
                        } else {
                            StepRow(state: .done, title: "scan.step.captured.photo", detail: "scan.step.captured.photo.detail")
                        }
                        Divider().overlay(Theme.divider)
                        StepRow(state: stage == .readingText ? .active : .done,
                                title: "scan.step.reading", detail: "scan.step.reading.detail")
                        Divider().overlay(Theme.divider)
                        StepRow(state: stage == .readingText ? .pending : .active,
                                title: "scan.step.understanding", detail: "scan.step.understanding.detail")
                    }
                    .card(padding: Spacing.m)

                    Label("scan.privacy", systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Spacing.m)
            }
        }
        .screenInset()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scan.progress")
    }
}

/// One step: what happens, and its state in words on the right ("Done", a spinner, "Waiting").
private struct StepRow: View {
    enum State { case done, active, pending }

    let state: State
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        AdaptiveStack(verticalAlignment: .center, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(state == .active ? .semibold : .regular))
                    .foregroundStyle(state == .pending ? Theme.secondaryText : Theme.text)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            // Wrap instead of truncating when the text size is large.
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.xs)
            status
        }
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var status: some View {
        switch state {
        case .done:
            Label("scan.step.done", systemImage: "checkmark")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.success)
        case .active:
            ProgressView()
                .tint(Theme.accent)
                .accessibilityLabel(Text("scan.step.inProgress"))
        case .pending:
            Text("scan.step.waiting")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// The receipt could not be read: what to do next. Scan again (camera), choose another photo,
/// or type the expense in. Cancelling the camera or the picker leaves this screen as it was; a
/// new image starts reading again in place.
struct ScanErrorView: View {
    let session: ScanSession
    let error: ExtractionError
    let onManual: () -> Void
    let close: () -> Void

    @State private var cameraRequested = false
    @State private var photoRequested = false

    private let cameraAvailable = DocumentCameraView.isAvailable

    var body: some View {
        StatusScreen(
            systemImage: "doc.text.magnifyingglass",
            iconTint: Theme.warningText,
            iconFill: Theme.warningFill,
            title: title,
            message: message,
            closeIdentifier: "scan.error.close",
            onClose: close
        ) {
            // The way the receipt came in is offered first.
            if session.source == .camera && cameraAvailable {
                scanAgain.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                anotherPhoto.buttonStyle(SecondaryButtonStyle(fullWidth: true))
            } else {
                anotherPhoto.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                if cameraAvailable {
                    scanAgain.buttonStyle(SecondaryButtonStyle(fullWidth: true))
                }
            }
            Button(action: onManual) { Text("scan.error.manual") }
                .buttonStyle(TextButtonStyle())
                .accessibilityIdentifier("scan.error.manual")
        }
        .scanSources(session: session, cameraRequested: $cameraRequested,
                     photoRequested: $photoRequested, onManual: onManual)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scan.error")
    }

    private var scanAgain: some View {
        Button { cameraRequested = true } label: { Text("scan.error.scanAgain") }
            .accessibilityIdentifier("scan.error.scanAgain")
    }

    private var anotherPhoto: some View {
        Button { photoRequested = true } label: { Text("scan.error.anotherPhoto") }
            .accessibilityIdentifier("scan.error.photo")
    }

    private var title: LocalizedStringKey {
        error == .noTextFound ? "scan.error.noText.title" : "scan.error.unreadable.title"
    }

    private var message: LocalizedStringKey {
        error == .noTextFound ? "scan.error.noText.message" : "scan.error.unreadable.message"
    }
}
