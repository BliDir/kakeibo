import KakeiboCore
import KakeiboScan
import SwiftUI

/// Full-screen scan flow: progress, then an error or the result.
struct ScanFlowView: View {
    let session: ScanSession

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            switch session.phase {
            case .idle:
                EmptyView()
            case .processing(let stage):
                ScanProgressView(session: session, stage: stage)
            case .failed(let error):
                ScanErrorView(error: error, retry: retry, close: session.cancel)
            case .finished:
                if let result = session.result {
                    ScanResultPreview(result: result, done: session.reset)
                }
            }
        }
    }

    private func retry() {
        if let data = session.imageData {
            session.start(imageData: data)
        } else if let image = session.image, let source = session.source {
            session.start(image: image, source: source)
        } else {
            session.cancel()
        }
    }
}

/// "Reading your receipt": the captured page and the pipeline's steps.
struct ScanProgressView: View {
    let session: ScanSession
    let stage: ExtractionStage

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("scan.progress.cancel", action: session.cancel)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border))
                    .accessibilityIdentifier("scan.cancel")
                Spacer()
                if session.source == .camera {
                    Text("scan.progress.pageCaptured")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            if let image = session.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .background(Theme.surface)
                    .shadow(color: .black.opacity(0.18), radius: 15, y: 10)
                    .rotationEffect(.degrees(-1.2))
                    .padding(.horizontal, 60)
                    .padding(.top, 22)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                Spacer()
            }

            progressSheet
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scan.progress")
    }

    private var progressSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("scan.progress.title")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.text)
                Text("scan.progress.subtitle")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 14) {
                if session.source == .camera {
                    StepRow(state: .done, title: "scan.step.captured.camera", detail: "scan.step.captured.camera.detail")
                } else {
                    StepRow(state: .done, title: "scan.step.captured.photo", detail: "scan.step.captured.photo.detail")
                }
                StepRow(state: stage == .readingText ? .active : .done,
                        title: "scan.step.reading", detail: "scan.step.reading.detail")
                StepRow(state: stage == .readingText ? .pending : .active,
                        title: "scan.step.understanding", detail: "scan.step.understanding.detail")
            }

            Divider().overlay(Theme.divider)
            Label("scan.privacy", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.08), radius: 10, y: -2)
    }
}

private struct StepRow: View {
    enum State { case done, active, pending }

    let state: State
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            indicator
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.body.weight(state == .active ? .bold : .medium))
                    .foregroundStyle(state == .active ? Theme.accent : state == .done ? Theme.text : Theme.secondaryText)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var indicator: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Theme.success, in: Circle())
        case .active:
            ProgressView().tint(Theme.accent)
        case .pending:
            Circle().stroke(Theme.pending, lineWidth: 2)
        }
    }
}

/// What went wrong, in words the user can act on.
struct ScanErrorView: View {
    let error: ExtractionError
    let retry: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundStyle(Theme.destructive)
                .accessibilityHidden(true)
            Text(title).font(.title3.bold()).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
            Spacer()
            Button(action: retry) { Text("scan.error.tryAgain").frame(maxWidth: .infinity) }
                .buttonStyle(PillButtonStyle())
            Button("scan.error.close", action: close)
                .frame(minHeight: 44)
                .foregroundStyle(Theme.accent)
        }
        .padding(24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scan.error")
    }

    private var title: LocalizedStringKey {
        error == .noTextFound ? "scan.error.noText.title" : "scan.error.unreadable.title"
    }

    private var message: LocalizedStringKey {
        error == .noTextFound ? "scan.error.noText.message" : "scan.error.unreadable.message"
    }
}

/// Temporary result screen. T-42 replaces it with the review and edit screen.
struct ScanResultPreview: View {
    let result: ExtractionResult
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("scan.result.title").font(.title2.bold()).foregroundStyle(Theme.text)
            VStack(alignment: .leading, spacing: 12) {
                row("scan.result.store", result.draft.storeName)
                row("scan.result.date", result.draft.dayKey)
                row("scan.result.total", result.draft.totalYen.map(Yen.format), id: "scan.result.total")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            Spacer()
            Button(action: done) { Text("scan.result.done").frame(maxWidth: .infinity) }
                .buttonStyle(PillButtonStyle())
                .accessibilityIdentifier("scan.result.done")
        }
        .padding(24)
    }

    private func row(_ label: LocalizedStringKey, _ value: String?, id: String? = nil) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.secondaryText)
            Spacer()
            Group {
                if let value { Text(verbatim: value) } else { Text("scan.result.notFound") }
            }
            .font(.body.monospacedDigit().weight(.semibold))
            .foregroundStyle(Theme.text)
            .accessibilityIdentifier(id ?? "")
        }
    }
}
