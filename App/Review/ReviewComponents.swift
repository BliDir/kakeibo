import KakeiboCore
import SwiftUI

/// A white rounded section; amber border when it holds a field to check.
struct Card<Content: View>: View {
    var highlight = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                if highlight { RoundedRectangle(cornerRadius: 14).stroke(Theme.warning, lineWidth: 2) }
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
    init(_ key: LocalizedStringKey) { self.key = key }

    var body: some View {
        Label(key, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(Theme.warningText)
            .accessibilityIdentifier("review.hint")
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
                Circle().fill(category.color).frame(width: 8, height: 8)
                Text(verbatim: "\(category.englishName) \(category.japaneseName)")
            }
            .font(.footnote.weight(selected ? .bold : .regular))
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(selected ? Theme.accentTint : Theme.field, in: Capsule())
            .overlay(Capsule().stroke(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2 : 1))
            .foregroundStyle(selected ? Theme.accent : Theme.text)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("category.\(category.rawValue)")
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

    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.text)
            Spacer()
            HStack(spacing: 1) {
                Text(verbatim: "¥")
                TextField(text: $value, prompt: Text(verbatim: "–")) { Text(label) }
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    .accessibilityIdentifier(id)
            }
            .font(.system(.subheadline, design: .monospaced))
        }
        .padding(.vertical, 10)
    }
}

/// One receipt item: name, English name, rate tag and price; discounts in vermilion.
struct ItemRow: View {
    let item: LineItemDraft

    var body: some View {
        HStack(spacing: 10) {
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
            Text(verbatim: Yen.format(item.priceYen))
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(item.priceYen < 0 ? Theme.destructive : Theme.text)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("review.item")
    }
}

/// An in-app confirmation (not a system alert): dimmed backdrop and a card with two buttons.
struct ConfirmPanel: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)
            VStack(spacing: 14) {
                Text(title).font(.headline).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                Text(message).font(.subheadline).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
                Button(action: onConfirm) {
                    Text(confirmTitle).font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .background(Theme.destructive, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
                .accessibilityIdentifier("confirm.action")
                Button(action: onCancel) {
                    Text("confirm.keepEditing").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .foregroundStyle(Theme.accent)
                .accessibilityIdentifier("confirm.cancel")
            }
            .padding(20)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
            .padding(16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("confirm")
        }
        .transition(.opacity)
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
            Color.black.ignoresSafeArea()
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
            .foregroundStyle(.white)
            .accessibilityLabel(Text("photo.close"))
            .accessibilityIdentifier("photo.close")
            .padding()
        }
    }
}
