import KakeiboScan
import PhotosUI
import SwiftUI

/// The ledger's three ways to add an expense: Scan (solid, the main action), Photo and Manual
/// (soft-glass secondary). Scan opens the VisionKit document camera, Photo the system photo
/// picker, Manual an empty review form. They sit side by side, and stack at the accessibility
/// text sizes. Without a document camera (the simulator) Scan stays visible but disabled,
/// with a hint to choose a photo instead.
struct ScanEntryButtons: View {
    let session: ScanSession
    let onManual: () -> Void

    @State private var showCamera = false
    @State private var showCameraDenied = false
    @State private var photoItem: PhotosPickerItem?
    @Environment(\.isAccessibilityTextSize) private var isAccessibilityTextSize

    private let cameraAvailable = DocumentCameraView.isAvailable

    var body: some View {
        Group {
            if isAccessibilityTextSize {
                VStack(spacing: Spacing.xs) { tiles }
            } else {
                HStack(spacing: 10) { tiles }
                .fixedSize(horizontal: false, vertical: true)
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

    @ViewBuilder private var tiles: some View {
        scan
        photo
        manual
    }

    private var scan: some View {
        Button {
            Task { await openCamera() }
        } label: {
            TileLabel(title: "scan.action.scan.short", systemImage: "doc.viewfinder")
        }
        .buttonStyle(PrimaryButtonStyle(fullWidth: true, shape: .tile))
        .disabled(!cameraAvailable)
        .accessibilityLabel(Text("scan.action.scan"))
        .accessibilityHint(cameraAvailable ? Text(verbatim: "") : Text("scan.camera.unavailable"))
        .accessibilityIdentifier("scan.camera")
    }

    private var photo: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            TileLabel(title: "scan.action.photo.short", systemImage: "photo.on.rectangle")
        }
        .buttonStyle(SecondaryButtonStyle(fullWidth: true, shape: .tile))
        .accessibilityLabel(Text("scan.action.photo"))
        .accessibilityIdentifier("scan.photo")
    }

    private var manual: some View {
        Button(action: onManual) {
            TileLabel(title: "scan.action.manual", systemImage: "square.and.pencil")
        }
        .buttonStyle(SecondaryButtonStyle(fullWidth: true, shape: .tile))
        .accessibilityLabel(Text("ledger.add"))
        .accessibilityIdentifier("ledger.add")
    }

    private func openCamera() async {
        if await CameraPermission.request() {
            showCamera = true
        } else {
            showCameraDenied = true
        }
    }
}

/// Icon over label in a tile; icon beside label at the accessibility sizes, where each tile is
/// a full-width row.
private struct TileLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    @Environment(\.isAccessibilityTextSize) private var isAccessibilityTextSize

    var body: some View {
        Group {
            if isAccessibilityTextSize {
                HStack(spacing: Spacing.xs) { icon; Text(title) }
            } else {
                VStack(spacing: 6) { icon; Text(title).lineLimit(2).minimumScaleFactor(0.8) }
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var icon: some View {
        Image(systemName: systemImage).font(.title3.weight(.medium)).accessibilityHidden(true)
    }
}
