import KakeiboCore
import SwiftUI

/// A rounded section on the soft grey surface; amber border when it holds a field to check.
struct Card<Content: View>: View {
    var highlight = false
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlight ? Theme.warningFill : Theme.surface, in: shape)
            .overlay {
                if highlight { shape.stroke(Theme.warning, lineWidth: 2) }
            }
    }
}

struct FieldLabel: View {
    let key: LocalizedStringKey
    init(_ key: LocalizedStringKey) { self.key = key }

    var body: some View {
        Text(key).font(.caption).foregroundStyle(Theme.secondaryText)
    }
}

/// "Check the amount": a short amber hint under an uncertain field.
struct Hint: View {
    let key: LocalizedStringKey
    /// False when the field itself announces the hint (`checkHint`), so VoiceOver does not say it twice.
    var announced = true
    init(_ key: LocalizedStringKey, announced: Bool = true) {
        self.key = key
        self.announced = announced
    }

    var body: some View {
        Label(key, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(Theme.warningText)
            .accessibilityHidden(!announced)
            .accessibilityIdentifier("review.hint")
    }
}

extension View {
    /// Says "Check the amount" (etc.) after the field's label when the scan was unsure,
    /// so the amber highlight is not only a color.
    func checkHint(_ needsCheck: Bool, _ key: LocalizedStringKey) -> some View {
        accessibilityHint(needsCheck ? Text(key) : Text(verbatim: ""))
    }
}

extension View {
    /// The design's input look; amber when the field needs checking.
    func inputStyle(highlight: Bool) -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(highlight ? Theme.warningFill : Theme.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(highlight ? Theme.warning : Theme.border, lineWidth: highlight ? 2 : 1)
            )
    }
}

/// A category chip: color dot, English and Japanese name.
struct CategoryChip: View {
    let category: ExpenseCategory
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(category.color)
                    .accessibilityHidden(true)
                // UI language first: "食料品 Groceries" / "Groceries 食料品".
                Text(verbatim: category.pairedLabel)
            }
            .font(.footnote.weight(selected ? .bold : .regular))
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(selected ? Theme.accentTint : Theme.field, in: Capsule())
            .overlay(Capsule().stroke(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2 : 1))
            .foregroundStyle(selected ? Theme.accent : Theme.text)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("category.\(category.rawValue)")
    }
}

/// Picks a payment method. A menu with its own label instead of a menu-style `Picker`, so the
/// label wraps at large text sizes instead of being cut off. VoiceOver reads the visible choice
/// ("Cash · 現金, pop-up button") after the field label above it.
struct PaymentMenu: View {
    let title: LocalizedStringKey
    @Binding var selection: PaymentMethod
    var highlight = false

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(PaymentMethod.allCases, id: \.self) { method in
                    Text(verbatim: method.label).tag(method)
                }
            } label: { Text(title) }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: selection.label)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .inputStyle(highlight: highlight)
        }
    }
}

/// Lays children out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if extra > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// A label and an editable yen amount on one row (tax lines).
struct YenRow: View {
    let label: LocalizedStringKey
    @Binding var value: String
    let id: String
    @Environment(\.isAccessibilityTextSize) private var isAccessibilityTextSize

    var body: some View {
        AdaptiveStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            HStack(spacing: 1) {
                let symbol = Yen.fieldSymbol(for: LedgerFormat.language)
                if symbol.isPrefix { Text(verbatim: symbol.symbol) }
                TextField(text: $value, prompt: Text(verbatim: "–")) { Text(label) }
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: isAccessibilityTextSize ? .infinity : 90)
                    .accessibilityIdentifier(id)
                if !symbol.isPrefix { Text(verbatim: symbol.symbol) }
            }
            .font(.amountSmall)
        }
        .padding(.vertical, 10)
    }
}

/// One receipt item: name, English name, rate tag and price; discounts in vermilion.
struct ItemRow: View {
    let item: LineItemDraft

    var body: some View {
        AdaptiveStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: item.name).foregroundStyle(Theme.text)
                if let english = item.nameEn {
                    Text(verbatim: english).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: item.isReducedRate ? "8%" : "10%")
                .font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(item.isReducedRate ? Theme.reducedRateFill : Theme.divider, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(item.isReducedRate ? Theme.reducedRateText : Theme.standardRateText)
            YenText(item.priceYen)
                .font(.amountSmall)
                .foregroundStyle(item.priceYen < 0 ? Theme.destructive : Theme.text)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("review.item")
    }
}

/// A screen's top bar: a leading action, the title centered, trailing actions. At the
/// accessibility text sizes the title moves under the buttons instead of drawing over them.
struct TitleBar<Leading: View, Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.isAccessibilityTextSize) private var isAccessibilityTextSize

    var body: some View {
        Group {
            if isAccessibilityTextSize {
                VStack(alignment: .leading, spacing: 4) {
                    buttons
                    titleText.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                CenteredTitleLayout(spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) { leading }.fixedSize()
                    titleText
                    HStack(spacing: Spacing.xs) { trailing }.fixedSize()
                }
            }
        }
        .screenInset()
        .padding(.top, Spacing.xs)
        .padding(.bottom, 4)
    }

    private var titleText: some View {
        Text(title).font(.screenTitle).foregroundStyle(Theme.text)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var buttons: some View {
        HStack(spacing: Spacing.xs) {
            leading
            Spacer()
            trailing
        }
    }
}

/// Leading side, title, trailing side: both sides get the width of the wider one, so the title
/// stays centered and never runs into a tag or a debug button. When that would leave the title
/// less than `minimumTitleWidth`, the title goes on its own line under the two sides.
struct CenteredTitleLayout: Layout {
    var spacing: CGFloat = 8
    var minimumTitleWidth: CGFloat = 120

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 390
        let plan = plan(width, subviews)
        return CGSize(width: width, height: plan.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let plan = plan(bounds.width, subviews)
        let rowMid = bounds.minY + plan.rowHeight / 2
        subviews[0].place(at: CGPoint(x: bounds.minX, y: rowMid), anchor: .leading, proposal: .unspecified)
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: rowMid), anchor: .trailing, proposal: .unspecified)
        let titleProposal = ProposedViewSize(width: plan.titleWidth, height: nil)
        if plan.stacked {
            subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.minY + plan.rowHeight + 4),
                              anchor: .top, proposal: titleProposal)
        } else {
            subviews[1].place(at: CGPoint(x: bounds.midX, y: rowMid), anchor: .center, proposal: titleProposal)
        }
    }

    private struct Plan { var stacked: Bool; var titleWidth: CGFloat; var rowHeight: CGFloat; var height: CGFloat }

    private func plan(_ width: CGFloat, _ subviews: Subviews) -> Plan {
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[2].sizeThatFits(.unspecified)
        let side = max(leading.width, trailing.width)
        let sideHeight = max(leading.height, trailing.height)
        let centered = width - 2 * (side + spacing)
        if centered >= minimumTitleWidth {
            let titleHeight = subviews[1].sizeThatFits(ProposedViewSize(width: centered, height: nil)).height
            let row = max(sideHeight, titleHeight)
            return Plan(stacked: false, titleWidth: centered, rowHeight: row, height: row)
        }
        let titleHeight = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return Plan(stacked: true, titleWidth: width, rowHeight: sideHeight, height: sideHeight + 4 + titleHeight)
    }
}

/// An in-app confirmation (never a system alert), on the shared `ActionPanel`.
///
/// - Delete-style (default): the vermilion confirm first, then a soft "keep" button.
/// - `keepFirst` (discard): "Keep editing" is the green main action and the destructive
///   choice is the vermilion text button under it, so the safe choice is the obvious one.
struct ConfirmPanel<Content: View>: View {
    var systemImage = "trash"
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    var keepTitle: LocalizedStringKey = "confirm.keepEditing"
    var keepFirst = false
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ActionPanel(systemImage: systemImage, tone: keepFirst ? .warning : .destructive,
                    title: title, message: message, onDismiss: onCancel) {
            content
        } actions: {
            if keepFirst {
                keepButton.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                confirmButton.buttonStyle(DestructiveButtonStyle())
            } else {
                confirmButton.buttonStyle(DestructiveButtonStyle(filled: true))
                keepButton.buttonStyle(SecondaryButtonStyle(fullWidth: true))
            }
        }
        .accessibilityIdentifier("confirm")
    }

    private var confirmButton: some View {
        Button(action: onConfirm) { Text(confirmTitle) }
            .accessibilityIdentifier("confirm.action")
    }

    private var keepButton: some View {
        Button(action: onCancel) { Text(keepTitle) }
            .accessibilityIdentifier("confirm.cancel")
    }
}

extension ConfirmPanel where Content == EmptyView {
    init(systemImage: String = "trash", title: LocalizedStringKey, message: LocalizedStringKey,
         confirmTitle: LocalizedStringKey, keepTitle: LocalizedStringKey = "confirm.keepEditing",
         keepFirst: Bool = false, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.init(systemImage: systemImage, title: title, message: message, confirmTitle: confirmTitle,
                  keepTitle: keepTitle, keepFirst: keepFirst, onConfirm: onConfirm, onCancel: onCancel,
                  content: { EmptyView() })
    }
}

/// "Not saved yet": a save (or delete) failed. Nothing was lost: the form is still there behind
/// the panel, so the user can try again at once or go back and change something.
struct FailurePanel: View {
    enum Kind { case save, delete }

    let kind: Kind
    let summary: EntrySummary
    let onRetry: () -> Void
    let onBack: () -> Void

    var body: some View {
        ActionPanel(
            systemImage: "exclamationmark.icloud",
            tone: .destructive,
            title: kind == .save ? "failure.save.title" : "failure.delete.title",
            message: kind == .save ? "failure.save.message" : "failure.delete.message",
            onDismiss: onBack
        ) {
            summary
        } actions: {
            Button(action: onRetry) {
                Text(kind == .save ? "failure.save.retry" : "failure.delete.retry")
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            .accessibilityIdentifier("failure.retry")
            Button(action: onBack) {
                Text(kind == .save ? "failure.save.back" : "failure.delete.back")
            }
            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
            .accessibilityIdentifier("failure.back")
        }
        .accessibilityIdentifier("failure")
    }
}

/// "Receipt captured · サンプルマート · Nov 5, 14:32 ›": the receipt photo as a row that opens it
/// full screen to compare with the form.
struct ReceiptLink: View {
    let image: UIImage?
    let title: LocalizedStringKey
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Image(systemName: "doc.text.image")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.accentTint)
                    }
                }
                .frame(width: 44, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.border))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    if !subtitle.isEmpty {
                        Text(verbatim: subtitle).font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.s)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("review.photo.view"))
        .accessibilityAddTraits(.isButton)
    }
}

extension ExpenseCategory {
    /// "食料品 Groceries" / "Groceries 食料品": the UI language first.
    var pairedLabel: String {
        LedgerFormat.language == .ja ? "\(japaneseName) \(englishName)" : "\(englishName) \(japaneseName)"
    }
}

/// The receipt photo full screen, pinch to zoom, double-tap to reset.
struct PhotoZoomView: View {
    let image: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.photoBackdrop.ignoresSafeArea()
            if let image {
                GeometryReader { proxy in
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width * scale)
                            .frame(minHeight: proxy.size.height)
                    }
                }
                .gesture(MagnifyGesture()
                    .onChanged { scale = min(max(lastScale * $0.magnification, 1), 5) }
                    .onEnded { _ in lastScale = scale })
                .onTapGesture(count: 2) { scale = 1; lastScale = 1 }
                .accessibilityLabel(Text("review.photo.view"))
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .foregroundStyle(Theme.onPhoto)
            .accessibilityLabel(Text("photo.close"))
            .accessibilityIdentifier("photo.close")
            .padding()
        }
    }
}
