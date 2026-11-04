import KakeiboScan
import PhotosUI
import SwiftUI

/// "Scan receipt" and "Choose photo", at the bottom of the ledger.
/// On the simulator (no document camera) only "Choose photo" is shown.
struct ScanEntryButtons: View {
    let session: ScanSession

    @State private var showCamera = false
    @State private var showCameraDenied = false
    @State private var photoItem: PhotosPickerItem?

    private let cameraAvailable = DocumentCameraView.isAvailable

    var body: some View {
        HStack(spacing: 10) {
            if cameraAvailable {
                Button {
                    Task { await openCamera() }
                } label: {
                    Label("scan.action.scan", systemImage: "doc.viewfinder")
                }
                .buttonStyle(PillButtonStyle())
                .accessibilityIdentifier("scan.camera")

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 54, height: 54)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().stroke(Theme.border))
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel(Text("scan.action.photo"))
                .accessibilityIdentifier("scan.photo")
            } else {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("scan.action.photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(PillButtonStyle())
                .accessibilityIdentifier("scan.photo")
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            DocumentCameraView(
                onScan: { image in
                    showCamera = false
                    session.start(image: image)
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showCameraDenied) {
            CameraAccessDeniedView()
                .presentationDetents([.medium])
        }
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
    }

    private func openCamera() async {
        if await CameraPermission.request() {
            showCamera = true
        } else {
            showCameraDenied = true
        }
    }
}

/// The indigo pill from the ledger design.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration)
    }

    /// At least 54 pt tall and grows with the text, so large text wraps instead of being cut off.
    /// Disabled: grey with secondary text, which keeps readable contrast (dimming did not).
    private struct Pill: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.button)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 26)
                .padding(.vertical, 10)
                .frame(minHeight: 54)
                .background(background, in: Capsule())
                .foregroundStyle(isEnabled ? Theme.onAccent : Theme.secondaryText)
                .shadow(color: isEnabled ? Theme.accent.opacity(0.35) : .clear, radius: 9, y: 6)
        }

        private var background: Color {
            guard isEnabled else { return Theme.divider }
            return configuration.isPressed ? Theme.accent.opacity(0.85) : Theme.accent
        }
    }
}
