import KakeiboCore
import KakeiboStore
import SwiftUI
import UIKit

/// The Settings tab: language, default payment, budget alerts, photo storage, privacy and version.
/// v1.0 has no account, so there is no login or account section.
struct SettingsView: View {
    let model: SettingsModel
    let notifier: BudgetNotifier
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("settings.title")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                general
                alerts
                data
                privacy
                about
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.groundLight.ignoresSafeArea())
        .task { await model.refreshPhotoUsage() }
        .task { await notifier.refreshAuthorization() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings")
    }

    // MARK: General

    private var general: some View {
        SettingsSection("settings.section.general", footer: "settings.language.footer") {
            // iOS keeps the app language per app; the system Settings page for this app has it.
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                SettingsRow("settings.language") {
                    Text("settings.language.value \(languageName)")
                    Image(systemName: "arrow.up.forward.app").font(.footnote).accessibilityHidden(true)
                }
            }
            .accessibilityHint(Text("settings.language.hint"))
            .accessibilityIdentifier("settings.language")

            Divider().overlay(Theme.divider)

            VStack(alignment: .leading, spacing: 6) {
                Text("settings.payment").foregroundStyle(Theme.text)
                PaymentMenu(title: "settings.payment", selection: Binding(
                    get: { model.settings.defaultPayment },
                    set: { model.settings.defaultPayment = $0 }
                ))
                .accessibilityIdentifier("settings.payment")
            }
            .padding(.vertical, 10)
        }
    }

    /// The language the app is showing now.
    private var languageName: String {
        LedgerFormat.language == .ja ? "日本語" : "English"
    }

    // MARK: Alerts

    /// Budget alerts: the app's own switch (off by default) and what iOS actually allows.
    /// The iOS prompt appears only when the user turns the switch on.
    private var alerts: some View {
        SettingsSection("settings.section.alerts", footer: "settings.alerts.footer") {
            Toggle(isOn: Binding(
                get: { notifier.isEnabled },
                set: { on in Task { await notifier.setEnabled(on) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.alerts.toggle")
                        .foregroundStyle(Theme.text)
                    Text("settings.alerts.toggle.detail")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .tint(Theme.accent)
            .disabled(notifier.isRequesting)
            .padding(.vertical, 10)
            .frame(minHeight: 50)
            .accessibilityIdentifier("settings.alerts")

            if notifier.needsSystemSettings {
                deniedHelp
                    .padding(.bottom, 12)
            }
            if notifier.requestFailed {
                Text("settings.alerts.failed")
                    .font(.footnote)
                    .foregroundStyle(Theme.warningText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
                    .accessibilityIdentifier("settings.alerts.failed")
            }

            Divider().overlay(Theme.divider)

            SettingsRow("settings.alerts.permission") {
                Text(permissionText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(permissionColor)
                    .accessibilityIdentifier("settings.alerts.permission")
            }
        }
    }

    /// Shown when the user wants alerts but iOS has notifications off for Kakeibo.
    private var deniedHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("settings.alerts.denied.title").font(.subheadline.weight(.bold))
            } icon: {
                Image(systemName: "exclamationmark.triangle").accessibilityHidden(true)
            }
            Text("settings.alerts.denied.body")
                .font(.footnote)
            Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            } label: {
                Text("settings.alerts.openSettings")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.warning))
            }
            .accessibilityIdentifier("settings.alerts.openSettings")
        }
        .foregroundStyle(Theme.warningText)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.warningFill, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.alerts.denied")
    }

    /// The real iOS permission, in words (not by color alone).
    private var permissionText: LocalizedStringKey {
        switch notifier.authorization {
        case .allowed: "settings.alerts.permission.allowed"
        case .denied: "settings.alerts.permission.denied"
        case .notDetermined: "settings.alerts.permission.notDetermined"
        }
    }

    private var permissionColor: Color {
        switch notifier.authorization {
        case .allowed: Theme.success
        case .denied: Theme.warningText
        case .notDetermined: Theme.secondaryText
        }
    }

    // MARK: Data

    private var data: some View {
        SettingsSection("settings.section.data") {
            SettingsRow("settings.photos") {
                Text(verbatim: photoUsageText)
                    .font(.amountSmall)
                    // Spoken without the "·": "1 photo, 96 KB".
                    .accessibilityLabel(Text(verbatim: photoUsageText.replacingOccurrences(of: " · ", with: ", ")))
                    .accessibilityIdentifier("settings.photos")
            }
        }
    }

    /// "12 photos · 4.2 MB".
    private var photoUsageText: String {
        if model.photoUsageFailed { return String(localized: "settings.photos.failed") }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false   // "0 KB", not "Zero KB"
        let size = formatter.string(fromByteCount: model.photoUsage.bytes)
        return String(localized: "settings.photos.count \(model.photoUsage.count)") + " · " + size
    }

    // MARK: Privacy

    private var privacy: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("settings.privacy.title").font(.headline)
                Text("settings.privacy.body").font(.subheadline)
            }
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.privacy")
    }

    // MARK: About

    private var about: some View {
        SettingsSection("settings.section.about") {
            // Ink-green wordmark in light mode, its ivory reverse in dark mode: no plate needed.
            BrandLogo(maxWidth: 180)
                .frame(maxHeight: 60)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("settings.logo")
            Divider().overlay(Theme.divider)
            SettingsRow("settings.version") {
                Text(verbatim: model.versionText)
                    .font(.amountSmall)
                    .accessibilityIdentifier("settings.version")
            }
        }
    }
}

/// A titled white card of rows, with an optional note under it.
private struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    let footer: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.overline).tracking(0.8)
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content }
                .padding(.horizontal, 16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// A label on the left and its value on the right, at least 50 pt tall.
private struct SettingsRow<Value: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder let value: Value

    init(_ label: LocalizedStringKey, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        // Label above the value at the accessibility text sizes.
        AdaptiveStack(spacing: 12) {
            Text(label).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            HStack(spacing: 6) { value }
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body)
        .padding(.vertical, 6)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}
