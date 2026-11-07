import KakeiboCore
import SwiftUI

/// An in-app panel over the current screen (UI-04): discard, delete, possible duplicate and
/// save failure. A dimmed backdrop and a bottom card with an icon tile, a title, a message, an
/// optional summary of the entry, and the actions stacked under it (the main one first).
///
/// The screen under it keeps all its state, so closing the panel always returns to the draft
/// as it was. Never a system alert. VoiceOver stays inside the panel while it is up.
struct ActionPanel<Content: View, Actions: View>: View {
    enum Tone {
        case accent, warning, destructive

        var tint: Color {
            switch self {
            case .accent: Theme.accent
            case .warning: Theme.warningText
            case .destructive: Theme.destructive
            }
        }

        var fill: Color {
            switch self {
            case .accent: Theme.accentTint
            case .warning: Theme.warningFill
            case .destructive: Theme.destructiveFill
            }
        }
    }

    let systemImage: String
    var tone: Tone = .accent
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    /// Tapping the backdrop: the same as the panel's "keep" action.
    let onDismiss: () -> Void
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        ZStack {
            Theme.scrim
                .ignoresSafeArea()
                .accessibilityHidden(true)
            // Always a scroll view, with the card at the bottom when it fits: a layout that
            // switched to scrolling only when needed swapped its views as text grew, and the
            // accessibility audit then saw text that did not scale.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: Spacing.l)
                        card
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    .background {
                        // Tapping outside the card closes it, like the panel's "keep" action.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onDismiss)
                            .accessibilityHidden(true)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        // A container, so an identifier given to the panel does not replace its children's.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .transition(.opacity)
    }

    private var card: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(tone.tint)
                .frame(width: 56, height: 56)
                .background(tone.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            content
            VStack(spacing: Spacing.xs) { actions }
                .padding(.top, 4)
        }
        .padding(Spacing.l)
        .frame(maxWidth: 520)
        .background(Theme.groundLight, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Theme.shadow, radius: 24, y: 8)
        .padding(.horizontal, Spacing.s)
        .padding(.bottom, Spacing.xs)
    }
}

extension ActionPanel where Content == EmptyView {
    init(systemImage: String, tone: Tone = .accent, title: LocalizedStringKey, message: LocalizedStringKey,
         onDismiss: @escaping () -> Void, @ViewBuilder actions: () -> Actions) {
        self.init(systemImage: systemImage, tone: tone, title: title, message: message, onDismiss: onDismiss,
                  content: { EmptyView() }, actions: actions)
    }
}

/// The entry a panel is about: category badge, store, a detail line or two, and the amount.
/// Read by VoiceOver as one element.
struct EntrySummary: View {
    let category: ExpenseCategory
    let storeName: String
    let amount: Int?
    let lines: [String]

    var body: some View {
        AdaptiveStack(verticalAlignment: .top, spacing: Spacing.s) {
            CategoryBadge(category: category, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if storeName.isEmpty {
                        Text("ledger.noStore").foregroundStyle(Theme.secondaryText)
                    } else {
                        Text(verbatim: storeName).foregroundStyle(Theme.text)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)
                ForEach(lines, id: \.self) { line in
                    Text(verbatim: line).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let amount {
                YenText(amount)
                    .font(.amount)
                    .foregroundStyle(Theme.text)
            }
        }
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
