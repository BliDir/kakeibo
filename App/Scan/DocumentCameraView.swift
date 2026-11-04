import SwiftUI
import VisionKit

/// VisionKit's document camera: finds the receipt's edges, captures automatically and
/// flattens the page. Returns the first page, upright.
struct DocumentCameraView: UIViewControllerRepresentable {
    var onScan: (CGImage) -> Void
    var onCancel: () -> Void

    /// False on the simulator and on devices without a camera.
    /// (`isSupported` alone returns true on the simulator, which has no camera.)
    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        VNDocumentCameraViewController.isSupported
        #endif
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    // VisionKit calls the delegate on the main thread but does not mark the protocol @MainActor.
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let parent: DocumentCameraView

        init(parent: DocumentCameraView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0, let image = scan.imageOfPage(at: 0).uprightCGImage else {
                parent.onCancel()
                return
            }
            parent.onScan(image)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            parent.onCancel()
        }
    }
}

private extension UIImage {
    /// The pixels as displayed, so OCR never sees a sideways image.
    var uprightCGImage: CGImage? {
        if imageOrientation == .up { return cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(at: .zero) }.cgImage
    }
}
