import KakeiboCore
import SwiftUI

/// A row that becomes a column at the accessibility text sizes (AX1–AX5), so text stacks
/// instead of being squeezed or cut off. Use it for any "label … value" or "icon text amount" row.
struct AdaptiveStack<Content: View>: View {
    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalAlignment: VerticalAlignment = .center
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: horizontalAlignment, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: verticalAlignment, spacing: spacing))
        layout { content }
    }
}

/// An amount as the screen shows it ("¥1,234" / "1,234円"), read by VoiceOver as
/// "1,234 yen" / "1,234円".
struct YenText: View {
    let amount: Int

    init(_ amount: Int) { self.amount = amount }

    var body: some View {
        Text(verbatim: LedgerFormat.yen(amount))
            .accessibilityLabel(Text(verbatim: LedgerFormat.spokenYen(amount)))
    }
}

/// Shows the content as is when it fits the height it is given, and in a scroll view when it
/// does not (a panel at the largest text sizes), so no button ends up off screen.
struct ScrollIfNeeded<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollBounceBehavior(.basedOnSize)
        }
    }
}

extension LedgerFormat {
    /// "1,234 yen" / "1,234円", for VoiceOver.
    static func spokenYen(_ amount: Int) -> String {
        Yen.spoken(amount, for: language)
    }

    /// "Thursday, November 5" / "11月5日 木曜日", for VoiceOver.
    static func spokenDay(_ dayKey: String) -> String {
        guard let date = DayKey.date(from: dayKey) else { return dayKey }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .ja ? "ja_JP" : "en_US")
        formatter.timeZone = KakeiboCore.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return formatter.string(from: date)
    }
}

extension EnvironmentValues {
    /// True at the accessibility text sizes, where layouts stack.
    var isAccessibilityTextSize: Bool { dynamicTypeSize.isAccessibilitySize }
}
