#if DEBUG
import KakeiboCore
import SwiftUI

/// Debug screen: the design system in the current appearance. Brand, every color, the type
/// scale, spacing, cards, headers, tags and every button style, including the opaque fallback
/// that Reduce Transparency and Increased Contrast use. Switch the iPhone between light and dark
/// while it is open: everything follows live. Debug only, so not localized.
struct DesignTokensView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static let colors: [(String, Color)] = [
        ("groundLight", Theme.groundLight), ("ground", Theme.ground), ("surface", Theme.surface),
        ("field", Theme.field), ("border", Theme.border), ("divider", Theme.divider),
        ("text", Theme.text), ("secondaryText", Theme.secondaryText), ("pending", Theme.pending),
        ("accent", Theme.accent), ("accentTint", Theme.accentTint), ("onAccent", Theme.onAccent),
        ("secondaryFill", Theme.secondaryFill), ("secondaryFillOpaque", Theme.secondaryFillOpaque),
        ("secondaryBorder", Theme.secondaryBorder),
        ("success", Theme.success), ("destructive 朱", Theme.destructive), ("onDestructive", Theme.onDestructive),
        ("destructiveFill", Theme.destructiveFill), ("destructiveText", Theme.destructiveText),
        ("warning", Theme.warning), ("warningFill", Theme.warningFill), ("warningText", Theme.warningText),
        ("reducedRateFill", Theme.reducedRateFill), ("reducedRateText", Theme.reducedRateText),
        ("standardRateText", Theme.standardRateText), ("scrim", Theme.scrim), ("shadow", Theme.shadow),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    environmentNote
                    brand
                    buttons
                    cards
                    type
                    spacing
                    colors
                    categories
                }
                .screenInset()
                .padding(.vertical, Spacing.m)
            }
            .background(Theme.groundLight)
            .navigationTitle(Text(verbatim: "Design system"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(Text("photo.close"))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tokens")
    }

    // MARK: Sections

    private var environmentNote: some View {
        Text(verbatim: "Appearance: \(colorScheme == .dark ? "dark" : "light") · contrast: \(contrast == .increased ? "increased" : "standard") · reduce transparency: \(reduceTransparency ? "on" : "off")")
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
            .accessibilityIdentifier("tokens.environment")
    }

    private var brand: some View {
        section("Brand") {
            BrandLogo(maxWidth: 200)
            Text(verbatim: "Original folded-K wordmark; ivory reverse in dark mode.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    private var buttons: some View {
        section("Buttons") {
            Button {} label: { Label { Text(verbatim: "Scan 読み取る") } icon: { Image(systemName: "doc.viewfinder") } }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            HStack(spacing: Spacing.xs) {
                Button {} label: { Label { Text(verbatim: "Photo") } icon: { Image(systemName: "photo.on.rectangle") } }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                Button {} label: { Label { Text(verbatim: "Manual") } icon: { Image(systemName: "plus") } }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
            }
            caption("Secondary on the ground: soft glass in light mode.")
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Button {} label: { Text(verbatim: "Export this month") }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                caption("Secondary on a card.")
                Button {} label: { Text(verbatim: "Export this month") }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true, forceOpaque: true))
                caption("Opaque fallback (Reduce Transparency, Increased Contrast, dark).")
            }
            .card(padding: Spacing.m)
            Button {} label: { Text(verbatim: "Save ¥1,310") }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .disabled(true)
            caption("Primary, disabled.")
            Button(role: .destructive) {} label: { Text(verbatim: "Delete expense 削除") }
                .buttonStyle(DestructiveButtonStyle())
            Button(role: .destructive) {} label: { Text(verbatim: "Delete 削除") }
                .buttonStyle(DestructiveButtonStyle(filled: true))
            HStack {
                Button {} label: { Text(verbatim: "Edit 編集") }.buttonStyle(TextButtonStyle())
                Button {} label: { Text(verbatim: "Close") }.buttonStyle(TextButtonStyle())
            }
        }
    }

    private var cards: some View {
        section("Header, card, tag") {
            ScreenHeader("tab.summary", eyebrow: "ledger.overline") {
                Button {} label: { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(TextButtonStyle())
                    .accessibilityLabel(Text(verbatim: "Export"))
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text(verbatim: "Recorded spending").eyebrow()
                    Spacer()
                    Tag(verbatim: "November")
                }
                Text(verbatim: "¥48,620").amountDisplay().foregroundStyle(Theme.text)
                Text(verbatim: "24 receipts · Tax included ¥3,920").font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            .card()
            Label { Text(verbatim: "Check the amount 金額を確認") } icon: { Image(systemName: "exclamationmark.triangle") }
                .font(.footnote).padding(Spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warningFill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .foregroundStyle(Theme.warningText)
            Label { Text(verbatim: "Verified 確認済み") } icon: { Image(systemName: "checkmark") }
                .font(.footnote).foregroundStyle(Theme.success)
        }
    }

    private var type: some View {
        section("Type (Dynamic Type)") {
            Text(verbatim: "Summary 集計").font(.pageTitle).foregroundStyle(Theme.text)
            Text(verbatim: "レシートを読み取り中").font(.sectionTitle).foregroundStyle(Theme.text)
            Text(verbatim: "確認して保存").font(.screenTitle).foregroundStyle(Theme.text)
            Text(verbatim: "Body 本文").font(.bodyText).foregroundStyle(Theme.text)
            Text(verbatim: "Today · ¥3,180").eyebrow()
            Text(verbatim: "Field label 店名").font(.fieldLabel).foregroundStyle(Theme.secondaryText)
            Text(verbatim: "¥1,310").font(.amountHero).foregroundStyle(Theme.text)
            Text(verbatim: "¥186,420").font(.amount).foregroundStyle(Theme.text)
            Text(verbatim: "¥72").font(.amountSmall).foregroundStyle(Theme.text)
            Text(verbatim: "T1234567890123").font(.code).foregroundStyle(Theme.text)
        }
    }

    private var spacing: some View {
        section("Spacing 8 · 12 · 16 · 24") {
            HStack(alignment: .bottom, spacing: Spacing.s) {
                ForEach([Spacing.xs, Spacing.s, Spacing.m, Spacing.l], id: \.self) { step in
                    VStack(spacing: 4) {
                        Rectangle().fill(Theme.accent).frame(width: step, height: step)
                        Text(verbatim: "\(Int(step))").font(.caption2).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
    }

    private var colors: some View {
        section("Colors") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: Spacing.xs) {
                ForEach(Self.colors, id: \.0) { name, color in
                    HStack(spacing: Spacing.xs) {
                        RoundedRectangle(cornerRadius: 6).fill(color)
                            .frame(width: 28, height: 28)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
                        Text(verbatim: name).font(.caption2).foregroundStyle(Theme.text)
                    }
                }
            }
        }
    }

    private var categories: some View {
        section("Categories") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: Spacing.xs) {
                ForEach(ExpenseCategory.allCases, id: \.self) { category in
                    HStack(spacing: Spacing.xs) {
                        CategoryBadge(category: category, size: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: category.englishName).font(.caption).foregroundStyle(Theme.text)
                            Text(verbatim: category.japaneseName).font(.caption2).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private func caption(_ text: String) -> some View {
        Text(verbatim: text).font(.caption2).foregroundStyle(Theme.secondaryText)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(verbatim: title).eyebrow()
            content()
        }
    }
}

#Preview("Light") { DesignTokensView().preferredColorScheme(.light) }
#Preview("Dark") { DesignTokensView().preferredColorScheme(.dark) }
#endif
