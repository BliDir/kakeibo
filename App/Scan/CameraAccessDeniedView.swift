import SwiftUI

/// Shown when camera access is off: a way to fix it in Settings, and the two ways to go on
/// without the camera (a photo, or typing the expense in).
struct CameraAccessDeniedView: View {
    let onChoosePhoto: () -> Void
    let onManual: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        StatusScreen(
            systemImage: "camera",
            title: "camera.denied.title",
            message: "camera.denied.message",
            closeIdentifier: "camera.denied.close",
            onClose: { dismiss() }
        ) {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                dismiss()
            } label: {
                Text("camera.denied.openSettings")
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            .accessibilityIdentifier("camera.denied.openSettings")

            Button(action: onChoosePhoto) { Text("camera.denied.choosePhoto") }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("camera.denied.photo")

            Button(action: onManual) { Text("camera.denied.manual") }
                .buttonStyle(TextButtonStyle())
                .accessibilityIdentifier("camera.denied.manual")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera.denied")
    }
}
