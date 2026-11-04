#if DEBUG
import KakeiboCore
import SwiftUI

/// Debug screen: every color, category and type style, in light and dark side by side.
struct DesignTokensView: View {
    @Environment(\.dismiss) private var dismiss

    private static let colors: [(String, Color)] = [
        ("groundLight", Theme.groundLight), ("ground", Theme.ground), ("surface", Theme.surface),
        ("field", Theme.field), ("border", Theme.border), ("divider", Theme.divider),
        ("text", Theme.text), ("secondaryText", Theme.secondaryText), ("pending", Theme.pending),
        ("accent 藍", Theme.accent), ("accentTint", Theme.accentTint), ("onAccent", Theme.onAccent),
        ("success", Theme.success), ("destructive 朱", Theme.destructive), ("onDestructive", Theme.onDestructive),
        ("warning", Theme.warning), ("warningFill", Theme.warningFill), ("warningText", Theme.warningText),
        ("reducedRateFill", Theme.reducedRateFill), ("reducedRateText", Theme.reducedRateText),
        ("standardRateText", Theme.standardRateText), ("scrim", Theme.scrim), ("shadow", Theme.shadow),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    column.environment(\.colorScheme, .light)
                    column.environment(\.colorScheme, .dark)
                }
            }
            .navigationTitle(Text(verbatim: "Design tokens"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(Text("photo.close"))
            }
        }
        .accessibilityIdentifier("tokens")
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Colors") {
                ForEach(Self.colors, id: \.0) { name, color in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 6).fill(color)
                            .frame(width: 28, height: 28)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
                        Text(verbatim: name).font(.caption2).foregroundStyle(Theme.text)
                    }
                }
            }
            section("Categories") {
                ForEach(ExpenseCategory.allCases, id: \.self) { category in
                    HStack(spacing: 8) {
                        CategoryBadge(category: category, size: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: category.englishName).font(.caption).foregroundStyle(Theme.text)
                            Text(verbatim: category.japaneseName).font(.caption2).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
            section("Type") {
                Text(verbatim: "¥1,310").font(.amountHero).foregroundStyle(Theme.text)
                Text(verbatim: "¥186,420").font(.amount).foregroundStyle(Theme.text)
                Text(verbatim: "¥72").font(.amountSmall).foregroundStyle(Theme.text)
                Text(verbatim: "確認して保存").font(.screenTitle).foregroundStyle(Theme.text)
                Text(verbatim: "レシートを読み取り中").font(.sectionTitle).foregroundStyle(Theme.text)
                Text(verbatim: "Body 本文").font(.bodyText).foregroundStyle(Theme.text)
                Text(verbatim: "AMOUNT PAID 税込").font(.overline).foregroundStyle(Theme.secondaryText)
                Text(verbatim: "Field label 店名").font(.fieldLabel).foregroundStyle(Theme.secondaryText)
                Text(verbatim: "T1234567890123").font(.code).foregroundStyle(Theme.text)
            }
            section("States") {
                Text(verbatim: "Save ¥1,310").font(.button).padding(10).frame(maxWidth: .infinity)
                    .background(Theme.accent, in: Capsule()).foregroundStyle(Theme.onAccent)
                Text(verbatim: "削除 Delete").font(.button).padding(10).frame(maxWidth: .infinity)
                    .background(Theme.destructive, in: Capsule()).foregroundStyle(Theme.onDestructive)
                Label { Text(verbatim: "Check the amount") } icon: { Image(systemName: "exclamationmark.triangle") }
                    .font(.caption).padding(8)
                    .background(Theme.warningFill, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.warning, lineWidth: 2))
                    .foregroundStyle(Theme.warningText)
                Label { Text(verbatim: "Verified") } icon: { Image(systemName: "checkmark") }
                    .font(.caption).foregroundStyle(Theme.success)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.groundLight)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title).font(.overline).foregroundStyle(Theme.secondaryText)
            content()
        }
    }
}

#Preview { DesignTokensView() }
#endif
