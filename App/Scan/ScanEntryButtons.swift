import KakeiboScan
import SwiftUI

/// The ledger's three ways to add an expense: Scan (solid, the main action), Photo and Manual
/// (soft-glass secondary). Scan opens the VisionKit document camera, Photo the system photo
/// picker, Manual an empty review form. They sit side by side, and stack at the accessibility
/// text sizes. Without a document camera (the simulator) Scan stays visible but disabled,
/// with a hint to choose a photo instead.
struct ScanEntryButtons: View {
    let session: ScanSession
    let onManual: () -> Void

    @State private var cameraRequested = false
    @State private var photoRequested = false
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
        .scanSources(session: session, cameraRequested: $cameraRequested,
                     photoRequested: $photoRequested, onManual: onManual)
    }

    @ViewBuilder private var tiles: some View {
        scan
        photo
        manual
    }

    private var scan: some View {
        Button { cameraRequested = true } label: {
            TileLabel(title: "scan.action.scan.short", systemImage: "doc.viewfinder")
        }
        .buttonStyle(PrimaryButtonStyle(fullWidth: true, shape: .tile))
        .disabled(!cameraAvailable)
        .accessibilityLabel(Text("scan.action.scan"))
        .accessibilityHint(cameraAvailable ? Text(verbatim: "") : Text("scan.camera.unavailable"))
        .accessibilityIdentifier("scan.camera")
    }

    private var photo: some View {
        Button { photoRequested = true } label: {
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
