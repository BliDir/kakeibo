import KakeiboCore
import KakeiboStore
import SwiftUI

/// The one in-app banner for a budget alert event (80% amber, 100% vermilion), shown whether
/// or not system notifications are allowed. In the foreground the iOS banner is hidden, so this
/// is the only one. It is not the persistent warning: the budget card shows that at all times.
struct BudgetAlertBannerView: View {
    let banner: BudgetAlertCoordinator.Banner
    let onDismiss: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: banner.threshold == .hundred ? "exclamationmark.circle.fill" : "bell.fill")
                .font(.title3)
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.text)
                detail
                    .font(.footnote)
                    .foregroundStyle(textColor)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Read as one line with spoken amounts: "80% of November's budget used. 36,600 yen left".
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: announcement))
            .accessibilityIdentifier("budget.alert.text")
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(textColor)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("budget.alert.dismiss"))
            .accessibilityIdentifier("budget.alert.dismiss")
        }
        .padding(.leading, 14)
        .padding(.vertical, 6)
        .background(fill, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(iconColor.opacity(0.4)))
        .shadow(color: Theme.shadow, radius: 12, y: 6)
        .padding(.horizontal, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(banner.threshold == .hundred ? "budget.alert.100" : "budget.alert.80")
        .task(id: banner.id) {
            AccessibilityNotification.Announcement(announcement).post()
            // Hides itself after a while; with VoiceOver on it stays until dismissed.
            guard !voiceOver else { return }
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }

    private var monthName: String { LedgerFormat.monthName(banner.month) }

    private var title: Text {
        banner.threshold == .hundred
            ? Text("budget.alert.100.title \(monthName)")
            : Text("budget.alert.80.title \(monthName)")
    }

    /// "¥36,600 left" or "Over by ¥4,350".
    private var detail: Text {
        guard let remaining = banner.remainingYen else { return Text(verbatim: "") }
        return remaining < 0
            ? Text("budget.alert.over \(LedgerFormat.yen(-remaining))")
            : Text("budget.alert.left \(LedgerFormat.yen(remaining))")
    }

    private var announcement: String {
        let title = banner.threshold == .hundred
            ? String(localized: "budget.alert.100.title \(monthName)")
            : String(localized: "budget.alert.80.title \(monthName)")
        guard let remaining = banner.remainingYen else { return title }
        let detail = remaining < 0
            ? String(localized: "budget.alert.over \(LedgerFormat.spokenYen(-remaining))")
            : String(localized: "budget.alert.left \(LedgerFormat.spokenYen(remaining))")
        return title + ". " + detail
    }

    private var fill: Color { banner.threshold == .hundred ? Theme.destructiveFill : Theme.warningFill }
    private var textColor: Color { banner.threshold == .hundred ? Theme.destructiveText : Theme.warningText }
    private var iconColor: Color { banner.threshold == .hundred ? Theme.destructive : Theme.warningText }
}
