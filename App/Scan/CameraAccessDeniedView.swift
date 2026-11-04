import SwiftUI

/// Shown when camera access is off, with a way to fix it in Settings.
struct CameraAccessDeniedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
                .frame(width: 72, height: 72)
                .background(Theme.accentTint, in: Circle())
                .accessibilityHidden(true)

            Text("camera.denied.title")
                .font(.title3.bold())
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)

            Text("camera.denied.message")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                dismiss()
            } label: {
                Text("camera.denied.openSettings").frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle())
            .accessibilityIdentifier("camera.denied.openSettings")

            Button("camera.denied.notNow") { dismiss() }
                .frame(minHeight: 44)
                .foregroundStyle(Theme.accent)
        }
        .padding(24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera.denied")
    }
}
