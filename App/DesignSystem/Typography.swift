import SwiftUI

/// The type scale. Every style follows Dynamic Type. Yen amounts use the system font with
/// monospaced (tabular) digits, so columns line up and numbers do not shift while typing.
extension Font {
    /// Large page titles ("Summary", "Settings"), 30 pt at the default size.
    static let pageTitle = Font.system(.largeTitle, weight: .semibold)
    /// Screen titles in sheet headers ("Check and save").
    static let screenTitle = Font.headline
    /// Card and panel titles ("Reading your receipt").
    static let sectionTitle = Font.title3.weight(.semibold)
    static let bodyText = Font.body
    static let bodyEmphasis = Font.body.weight(.medium)
    /// Field labels and small captions.
    static let fieldLabel = Font.caption
    /// Uppercase labels ("AMOUNT PAID"). Use `.eyebrow()` for the letter spacing and case.
    static let overline = Font.caption.weight(.semibold)
    static let footnoteText = Font.footnote
    /// Button labels.
    static let button = Font.system(.callout, weight: .semibold)

    /// The amount being typed or checked (review form, budget sheet).
    static let amountHero = Font.system(.largeTitle, weight: .medium).monospacedDigit()
    /// Amounts in rows and totals.
    static let amount = Font.system(.body, weight: .semibold).monospacedDigit()
    /// Smaller amounts (tax lines, item prices).
    static let amountSmall = Font.system(.subheadline).monospacedDigit()
    /// Codes such as the invoice number and raw OCR text.
    static let code = Font.system(.footnote, design: .monospaced)
}

extension View {
    /// The month's big total (52 pt at the default size), scaled with Dynamic Type like
    /// `.largeTitle`. Fonts with a fixed size do not scale, so this uses a scaled metric.
    func amountDisplay(size: CGFloat = 52) -> some View {
        modifier(ScaledAmountFont(size: size))
    }

    /// Small uppercase label with letter spacing ("TODAY · ¥3,180", "PREFERENCES"). Pass
    /// `uppercase: false` where the case matters: brand names ("iPhone") or words VoiceOver
    /// reads as part of a longer label.
    func eyebrow(uppercase: Bool = true) -> some View {
        font(.overline)
            .tracking(uppercase ? 1.2 : 0.6)
            .textCase(uppercase ? .uppercase : nil)
            .foregroundStyle(Theme.secondaryText)
    }
}

private struct ScaledAmountFont: ViewModifier {
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .medium).monospacedDigit())
            .tracking(-size * 0.04)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}
