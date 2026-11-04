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
        configuration.label
            .font(.button)
            .padding(.horizontal, 26)
            .frame(height: 54)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.85 : 1), in: Capsule())
            .foregroundStyle(Theme.onAccent)
            .shadow(color: Theme.accent.opacity(0.35), radius: 9, y: 6)
    }
}
