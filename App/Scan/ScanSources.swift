import KakeiboScan
import KakeiboStore
import PhotosUI
import SwiftUI

/// Where a new receipt image comes from: the VisionKit document camera or the system photo
/// picker. One place for the camera permission check, the "camera is off" sheet and photo
/// loading, used by the ledger's Scan / Photo tiles and by the read-error screen's
/// "Scan again" / "Choose another photo".
///
/// Set `cameraRequested` or `photoRequested` to true to start. A new image starts `session`
/// (from any phase, so a failed read is replaced in place); cancelling the camera or the picker
/// changes nothing.
struct ScanSources: ViewModifier {
    let session: ScanSession
    @Binding var cameraRequested: Bool
    @Binding var photoRequested: Bool
    /// "Add manually" from the camera-off sheet.
    let onManual: () -> Void

    @State private var showCamera = false
    @State private var showCameraDenied = false
    @State private var photoItem: PhotosPickerItem?
    /// What the camera-off sheet asked for, done once it has gone.
    @State private var afterDenied: AfterDenied?

    private enum AfterDenied { case photo, manual }

    func body(content: Content) -> some View {
        content
            .onChange(of: cameraRequested) { _, requested in
                guard requested else { return }
                cameraRequested = false
                Task { await openCamera() }
            }
            .photosPicker(isPresented: $photoRequested, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        session.start(imageData: data)
                    } else {
                        session.start(imageData: Data())   // shows "couldn't read this image"
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                DocumentCameraView(
                    onScan: { image in
                        showCamera = false
                        session.start(image: image, source: .camera)
                    },
                    onCancel: {
                        showCamera = false
                        // No page to read: VisionKit's copies can go at once (B-12).
                        try? ScratchFiles.clearScannedPages()
                    }
                )
                .ignoresSafeArea()
            }
            #if DEBUG
            .task { if Self.claimDebugCameraDenied() { showCameraDenied = true } }
            #endif
            .sheet(isPresented: $showCameraDenied, onDismiss: runAfterDenied) {
                CameraAccessDeniedView(
                    onChoosePhoto: { afterDenied = .photo; showCameraDenied = false },
                    onManual: { afterDenied = .manual; showCameraDenied = false }
                )
                // Full height, as in the design: a half-height sheet hides part of the panel.
                .presentationDetents([.large])
            }
    }

    private func openCamera() async {
        guard DocumentCameraView.isAvailable else { return }
        if await CameraPermission.request() {
            showCamera = true
        } else {
            showCameraDenied = true
        }
    }

    #if DEBUG
    /// UI tests: `KAKEIBO_SHOW_CAMERA_DENIED=1` opens the camera-off sheet once at launch, since
    /// the simulator has no camera to be denied.
    @MainActor private static var debugCameraDeniedShown = false

    @MainActor private static func claimDebugCameraDenied() -> Bool {
        guard ProcessInfo.processInfo.environment["KAKEIBO_SHOW_CAMERA_DENIED"] == "1", !debugCameraDeniedShown else { return false }
        debugCameraDeniedShown = true
        return true
    }
    #endif

    /// Two sheets cannot be up at once: the picker or the manual form opens after this one has gone.
    private func runAfterDenied() {
        guard let next = afterDenied else { return }
        afterDenied = nil
        switch next {
        case .photo: photoRequested = true
        case .manual: onManual()
        }
    }
}

extension View {
    func scanSources(session: ScanSession, cameraRequested: Binding<Bool>, photoRequested: Binding<Bool>,
                     onManual: @escaping () -> Void) -> some View {
        modifier(ScanSources(session: session, cameraRequested: cameraRequested,
                             photoRequested: photoRequested, onManual: onManual))
    }
}
