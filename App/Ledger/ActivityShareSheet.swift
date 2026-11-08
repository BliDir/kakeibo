import SwiftUI
import UIKit

/// The iOS share sheet for one file, which reports when it is finished (B-12). `ShareLink` has
/// no such callback, and an exported CSV must be deleted once it has been shared, saved or
/// cancelled.
///
/// Present it with `.sheet(item:onDismiss:)` and delete the file in `onDismiss`: the sheet
/// goes away after the chosen action has finished (or on Cancel, or a swipe down), so the
/// file is never removed while it is still being copied.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let url: URL
    /// Called when the share sheet has finished, whatever the outcome.
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
