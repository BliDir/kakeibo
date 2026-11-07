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
            VStack(alignment: .leading, spacing: Spacing.l) {
                ScreenHeader("settings.title")
                intro
                general
                alerts
                data
                privacy
                versionFooter
            }
            .screenInset()
            .padding(.top, Spacing.xs)
            .padding(.bottom, Spacing.l)
        }
        .background(Theme.groundLight.ignoresSafeArea())
        .task { await model.refreshPhotoUsage() }
        .task { await notifier.refreshAuthorization() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings")
    }

    // MARK: Intro

    /// The wordmark (ink green in light mode, its ivory reverse in dark mode) and the tagline.
    private var intro: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            BrandLogo(maxWidth: 150)
                .frame(maxHeight: 48, alignment: .leading)
                .accessibilityIdentifier("settings.logo")
            Text("settings.tagline")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Preferences

    private var general: some View {
        SettingsSection("settings.section.general", footer: "settings.language.footer") {
            // iOS keeps the app language per app; the system Settings page for this app has it.
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                SettingsRow("settings.language", systemImage: "globe",
                            detail: Text("settings.language.value \(languageName)")) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("settings.language.hint"))
            .accessibilityIdentifier("settings.language")

            Divider().overlay(Theme.divider)

            SettingsRow("settings.payment", systemImage: "creditcard", detail: Text("settings.payment.detail")) {
                CompactPaymentMenu(title: "settings.payment", selection: Binding(
                    get: { model.settings.defaultPayment },
                    set: { model.settings.defaultPayment = $0 }
                ))
                .accessibilityIdentifier("settings.payment")
            }
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
                HStack(spacing: Spacing.s) {
                    SettingsIcon(systemImage: "bell")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.alerts.toggle")
                            .foregroundStyle(Theme.text)
                        Text("settings.alerts.toggle.detail")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
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

            SettingsRow("settings.alerts.permission", systemImage: "app.badge") {
                Text(permissionText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(permissionColor)
                    .accessibilityIdentifier("settings.alerts.permission")
            }

            Divider().overlay(Theme.divider)

            thresholds
        }
    }

    /// When the two alerts come, in words, and that progress shows on the ledger either way.
    private var thresholds: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ThresholdRow(percent: "80%", message: "settings.alerts.80", tint: Theme.warningText)
            ThresholdRow(percent: "100%", message: "settings.alerts.100", tint: Theme.destructive)
            Label("settings.alerts.progressNote", systemImage: "chart.bar")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.alerts.thresholds")
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
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("settings.alerts.openSettings")
        }
        .foregroundStyle(Theme.warningText)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.s)
        .background(Theme.warningFill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
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

    // MARK: On this iPhone

    /// Receipt photos: how many, and how much space they take.
    private var data: some View {
        SettingsSection("settings.section.data") {
            SettingsRow("settings.photos", systemImage: "photo.on.rectangle",
                        detail: Text(verbatim: photoCountText)) {
                Text(verbatim: photoSizeText)
                    .font(.amountSmall)
            }
            // One element: "Receipt photos, 1 photo, 96 KB".
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("settings.photos"))
            .accessibilityValue(Text(verbatim: photoUsageSpoken))
            .accessibilityIdentifier("settings.photos")
        }
    }

    /// "12 photos", or "Couldn't read".
    private var photoCountText: String {
        if model.photoUsageFailed { return String(localized: "settings.photos.failed") }
        return String(localized: "settings.photos.count \(model.photoUsage.count)")
    }

    /// "4.2 MB" ("0 KB", not "Zero KB").
    private var photoSizeText: String {
        if model.photoUsageFailed { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: model.photoUsage.bytes)
    }

    /// "12 photos, 4.2 MB".
    private var photoUsageSpoken: String {
        model.photoUsageFailed ? photoCountText : "\(photoCountText), \(photoSizeText)"
    }

    // MARK: Privacy

    private var privacy: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: "checkmark.shield")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("settings.privacy.title").font(.headline)
                Text("settings.privacy.body").font(.subheadline)
            }
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.m + 4)
        .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.privacy")
    }

    // MARK: Version

    /// "Version 1.1 (42)": the real version and build from the app bundle.
    private var versionFooter: some View {
        HStack(spacing: 4) {
            Text("settings.version")
            Text(verbatim: model.versionText)
                .monospacedDigit()
                .accessibilityIdentifier("settings.version")
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondaryText)
        .frame(maxWidth: .infinity)
    }
}

/// An uppercase title, a card of rows, and an optional note under it.
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
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Not uppercased: that would turn "iPhone" into "IPHONE".
            Text(title)
                .eyebrow(uppercase: false)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, 4)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// "At 80%: A little room left. Time to check in." Read as one sentence.
private struct ThresholdRow: View {
    let percent: String
    let message: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(verbatim: percent)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .frame(minWidth: 44, alignment: .leading)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A row's icon: the symbol in accent green on a soft green tile.
private struct SettingsIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.medium))
            .foregroundStyle(Theme.accent)
            .frame(width: 36, height: 36)
            .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Icon, a label with an optional detail line under it, and a value or control on the right.
/// The value moves under the label at the accessibility text sizes.
private struct SettingsRow<Value: View>: View {
    let label: LocalizedStringKey
    let systemImage: String
    let detail: Text?
    @ViewBuilder let value: Value

    init(_ label: LocalizedStringKey, systemImage: String, detail: Text? = nil, @ViewBuilder value: () -> Value) {
        self.label = label
        self.systemImage = systemImage
        self.detail = detail
        self.value = value()
    }

    var body: some View {
        AdaptiveStack(spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                SettingsIcon(systemImage: systemImage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).foregroundStyle(Theme.text)
                    if let detail {
                        detail.font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.xs)
            HStack(spacing: 6) { value }
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

/// The default payment as a compact menu on the right of its row ("IC card ⌃⌄"). The menu
/// lists both languages; VoiceOver reads the visible choice after the row's label.
private struct CompactPaymentMenu: View {
    let title: LocalizedStringKey
    @Binding var selection: PaymentMethod

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(PaymentMethod.allCases, id: \.self) { method in
                    Text(verbatim: method.label).tag(method)
                }
            } label: { Text(title) }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: selection.shortLabel)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .frame(minHeight: minimumTapTarget)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: selection.label))
    }
}
