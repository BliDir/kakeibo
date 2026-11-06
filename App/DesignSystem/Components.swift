import SwiftUI

// Shared layout and components for the visual refresh (UI-01). Screens are moved onto them in
// UI-02 to UI-06; use these instead of one-off paddings, corner radii or button looks.

// MARK: - Spacing and shape

/// The spacing steps. Use these for stack spacing and padding.
enum Spacing {
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
}

/// Corner radii, always drawn continuous.
enum Radius {
    /// Cards and grouped rows.
    static let card: CGFloat = 22
    /// Tiles inside a card, banners, inputs.
    static let control: CGFloat = 14
    /// Small chips and tags.
    static let chip: CGFloat = 10
}

/// The smallest tap target, in points.
let minimumTapTarget: CGFloat = 44

extension View {
    /// The shared horizontal screen inset: 24 pt, or 20 / 16 pt on narrower screens.
    func screenInset() -> some View {
        modifier(ScreenInset())
    }

    /// A card: `Theme.surface`, 22 pt continuous corners, 20 pt padding by default.
    func card(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

private struct ScreenInset: ViewModifier {
    @State private var width: CGFloat = 402

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Self.inset(forWidth: width))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    /// 24 pt from 390 pt wide (iPhone 12 and later), 20 pt from 360 pt, 16 pt below.
    static func inset(forWidth width: CGFloat) -> CGFloat {
        width >= 390 ? Spacing.l : width >= 360 ? 20 : Spacing.m
    }
}

// MARK: - Header

/// A page header: an optional uppercase eyebrow, a large title, an optional subtitle, and
/// trailing actions (icon buttons) that move under the title at the accessibility sizes.
struct ScreenHeader<Trailing: View>: View {
    let eyebrow: LocalizedStringKey?
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @ViewBuilder let trailing: Trailing

    init(_ title: LocalizedStringKey, eyebrow: LocalizedStringKey? = nil, subtitle: LocalizedStringKey? = nil,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.eyebrow = eyebrow
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        AdaptiveStack(verticalAlignment: .top, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 4) {
                if let eyebrow { Text(eyebrow).eyebrow() }
                Text(title)
                    .font(.pageTitle)
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: Spacing.xs) { trailing }
        }
    }
}

// MARK: - Tag

/// A small rounded label on a soft green fill ("November", ".csv").
struct Tag: View {
    let text: Text

    init(_ key: LocalizedStringKey) { text = Text(key) }
    init(verbatim: String) { text = Text(verbatim: verbatim) }

    var body: some View {
        text
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.accentTint, in: Capsule())
    }
}

// MARK: - Buttons

/// Solid ink-green button for the main action of a screen (Scan, Save, a principal
/// confirmation). At least 54 pt tall; the label wraps at large text sizes instead of being
/// cut off. Disabled: grey fill with secondary text, which stays readable (dimming did not).
struct PrimaryButtonStyle: ButtonStyle {
    /// Stretch to the available width (sheet save bars) or hug the label (floating actions).
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, fullWidth: fullWidth)
    }

    private struct Styled: View {
        let configuration: Configuration
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.button)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 54)
                .foregroundStyle(isEnabled ? Theme.onAccent : Theme.secondaryText)
                .background(isEnabled ? Theme.accent : Theme.divider, in: Capsule())
                // Pressed: a darker overlay on the fill only; the label stays fully opaque.
                .overlay(Capsule().fill(Color.black.opacity(configuration.isPressed ? 0.14 : 0)))
                .contentShape(Capsule())
        }
    }
}

/// Secondary actions (Photo, Manual, Export). Light: soft glass, a translucent green-grey fill
/// over a material with a subtle green border. Dark, Reduce Transparency and Increased
/// Contrast: an opaque fill. The label and icon are always fully opaque.
struct SecondaryButtonStyle: ButtonStyle {
    var fullWidth = false
    /// Debug gallery: show the opaque fallback without changing system settings.
    var forceOpaque = false

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, fullWidth: fullWidth, forceOpaque: forceOpaque)
    }

    private struct Styled: View {
        let configuration: Configuration
        let fullWidth: Bool
        let forceOpaque: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

        /// Glass only in light mode with default settings.
        private var isGlass: Bool {
            !forceOpaque && colorScheme == .light && contrast == .standard && !reduceTransparency
        }

        var body: some View {
            configuration.label
                .font(.button)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 54)
                .foregroundStyle(isEnabled ? Theme.text : Theme.secondaryText)
                .background { fill }
                .overlay(Capsule().strokeBorder(Theme.secondaryBorder, lineWidth: contrast == .increased ? 1.5 : 1))
                .overlay(Capsule().fill(Color.black.opacity(configuration.isPressed ? 0.08 : 0)))
                .contentShape(Capsule())
        }

        @ViewBuilder private var fill: some View {
            if isGlass {
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Theme.secondaryFill))
            } else {
                Capsule().fill(Theme.secondaryFillOpaque)
            }
        }
    }
}

/// Destructive actions keep their own meaning: vermilion text on no fill (Delete, Remove), or a
/// solid vermilion button when `filled` (the confirm button of a delete panel). Never green.
struct DestructiveButtonStyle: ButtonStyle {
    var filled = false
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.button)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: filled ? 54 : 48)
            .foregroundStyle(filled ? Theme.onDestructive : Theme.destructive)
            .background(filled ? Theme.destructive : Color.clear, in: Capsule())
            .overlay(Capsule().fill(Color.black.opacity(configuration.isPressed ? (filled ? 0.14 : 0.06) : 0)))
            .contentShape(Capsule())
    }
}

/// A text-only action in the accent color ("Edit", "Close"), with a 44 pt tap target.
struct TextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 6)
            .frame(minWidth: minimumTapTarget, minHeight: minimumTapTarget)
            // Pressed: a soft highlight behind the label; the label itself stays fully opaque.
            .background(Theme.accentTint.opacity(configuration.isPressed ? 1 : 0), in: Capsule())
            .contentShape(Rectangle())
    }
}

/// Earlier name of `PrimaryButtonStyle` (the hugging pill); existing screens keep working.
typealias PillButtonStyle = PrimaryButtonStyle

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Brand

/// The Kakeibo wordmark: ink-green lettering in light mode, the ivory reverse (as on the app
/// icon) in dark mode, from the same asset. Needs no plate behind it.
struct BrandLogo: View {
    var maxWidth: CGFloat = 180

    var body: some View {
        Image("KakeiboLogo")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: maxWidth)
            .accessibilityLabel(Text(verbatim: "Kakeibo"))
            .accessibilityAddTraits(.isImage)
    }
}
