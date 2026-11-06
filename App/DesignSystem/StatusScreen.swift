import SwiftUI

/// A full-screen state from the visual refresh's "Exceptions and confirmations" (camera off,
/// receipt not readable, …): an optional Close in the corner, an icon tile, a large title, a
/// short message and the actions stacked under it (primary first). Scrolls when it does not fit,
/// so no action is pushed off screen at the largest text sizes or in a short sheet.
struct StatusScreen<Actions: View>: View {
    let systemImage: String
    var iconTint: Color = Theme.accent
    var iconFill: Color = Theme.accentTint
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var closeTitle: LocalizedStringKey = "scan.error.close"
    var closeIdentifier = "status.close"
    var onClose: (() -> Void)?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onClose {
                Button(closeTitle, action: onClose)
                    .buttonStyle(TextButtonStyle())
                    .accessibilityIdentifier(closeIdentifier)
                    .padding(.top, Spacing.xs)
            }
            // Always a scroll view, centred when it fits: nothing is squeezed or clipped in a
            // short sheet, and every text keeps scaling with Dynamic Type.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: Spacing.m) {
                        Image(systemName: systemImage)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(iconTint)
                            .frame(width: 68, height: 68)
                            .background(iconFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(spacing: Spacing.xs) {
                            Text(title)
                                .font(.title.weight(.bold))
                                .foregroundStyle(Theme.text)
                                .accessibilityAddTraits(.isHeader)
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: Spacing.s) { actions }
                            .padding(.top, Spacing.xs)
                    }
                    .padding(.vertical, Spacing.l)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .screenInset()
        .background(Theme.groundLight.ignoresSafeArea())
    }
}
