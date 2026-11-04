import KakeiboCore
import KakeiboStore
import SwiftUI

/// The ledger home screen: one month's spending at a glance.
struct LedgerView: View {
    let model: LedgerModel
    let photoStore: PhotoStore?
    let onSelect: (Expense) -> Void
    /// Debug builds only: opens the design tokens screen.
    var onShowTokens: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                summaryCard
                if model.isEmpty {
                    emptyState
                } else {
                    ForEach(model.days, id: \.dayKey) { day in
                        DaySection(day: day, photoStore: photoStore, onSelect: onSelect)
                    }
                }
                if model.loadFailed {
                    Text("ledger.loadFailed").font(.caption).foregroundStyle(Theme.destructive)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.groundLight.ignoresSafeArea())
    }

    // MARK: Header and month switcher

    private var header: some View {
        VStack(spacing: 2) {
            HStack {
                Text("ledger.overline")
                    .font(.overline).tracking(1)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                if let onShowTokens {
                    Button(action: onShowTokens) { Image(systemName: "hammer") }
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityLabel(Text(verbatim: "Design tokens"))
                        .accessibilityIdentifier("debug.tokens")
                }
            }
            HStack {
                MonthButton(systemImage: "chevron.left", label: "ledger.month.previous", id: "ledger.previous") {
                    model.showPrevious()
                }
                Spacer()
                VStack(spacing: 0) {
                    Text(verbatim: LedgerFormat.monthTitle(model.month))
                        .font(.title2.bold())
                        .foregroundStyle(Theme.text)
                        .accessibilityIdentifier("ledger.month")
                    Text(verbatim: LedgerFormat.eraSubtitle(model.month))
                        .font(.footnoteText)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer()
                MonthButton(systemImage: "chevron.right", label: "ledger.month.next", id: "ledger.next") {
                    model.showNext()
                }
                .disabled(!model.canShowNext)
                .opacity(model.canShowNext ? 1 : 0.35)
            }
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("ledger.total.label").font(.overline).tracking(1).foregroundStyle(Theme.secondaryText)
                Spacer()
                Text(verbatim: Yen.format(model.summary.totalYen))
                    .font(.amountHero)
                    .foregroundStyle(Theme.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .accessibilityIdentifier("ledger.total")
            }
            HStack {
                Text("ledger.receipts \(model.summary.count)")
                    .accessibilityIdentifier("ledger.count")
                Spacer()
                Text("ledger.tax \(Yen.format(model.summary.taxYen))")
            }
            .font(.footnoteText)
            .foregroundStyle(Theme.secondaryText)

            if !model.summary.categories.isEmpty {
                CategoryBar(categories: model.summary.categories)
                HStack(spacing: 12) {
                    ForEach(model.summary.categories.prefix(3), id: \.category) { entry in
                        HStack(spacing: 6) {
                            Circle().fill(entry.category.color).frame(width: 8, height: 8)
                            Text(verbatim: entry.category.displayName(for: LedgerFormat.language))
                        }
                    }
                }
                .font(.footnoteText)
                .foregroundStyle(Theme.text)
            }
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ledger.summary")
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("ledger.empty.title").font(.sectionTitle).foregroundStyle(Theme.text)
            Text("ledger.empty.message")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Image(systemName: "arrow.down")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ledger.empty")
    }
}

private struct MonthButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.border))
                .foregroundStyle(Theme.text)
        }
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(id)
    }
}

/// The month's spending split by category, as one bar.
private struct CategoryBar: View {
    let categories: [MonthSummary.CategoryTotal]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(categories, id: \.category) { entry in
                    entry.category.color
                        .frame(width: max(2, (proxy.size.width - CGFloat(categories.count - 1) * 2) * entry.share))
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// One day: its date, subtotal and expenses.
private struct DaySection: View {
    let day: DayGroup<Expense>
    let photoStore: PhotoStore?
    let onSelect: (Expense) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: LedgerFormat.dayTitle(day.dayKey))
                Spacer()
                Text(verbatim: Yen.format(day.subtotalYen)).font(.amountSmall)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.secondaryText)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(day.items.enumerated()), id: \.element.id) { index, expense in
                    if index > 0 { Divider().overlay(Theme.divider) }
                    Button { onSelect(expense) } label: {
                        LedgerRow(expense: expense, photoStore: photoStore)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ledger.row")
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// Thumbnail or category icon, store, category · payment · items, amount.
private struct LedgerRow: View {
    let expense: Expense
    let photoStore: PhotoStore?

    var body: some View {
        HStack(spacing: 12) {
            ReceiptThumbnail(name: expense.photoFileName, category: expense.category, photoStore: photoStore)
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if expense.storeName.isEmpty {
                        Text("ledger.noStore").foregroundStyle(Theme.secondaryText)
                    } else {
                        Text(verbatim: expense.storeName).foregroundStyle(Theme.text)
                    }
                }
                .font(.bodyEmphasis)
                .lineLimit(1)
                if let english = expense.storeNameEn {
                    Text(verbatim: english).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                details.font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: Yen.format(expense.totalYen))
                .font(.amount)
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "Groceries · IC card · 5 items".
    private var details: Text {
        var parts = [expense.category.displayName(for: LedgerFormat.language), expense.payment.shortLabel]
        if !expense.items.isEmpty {
            parts.append(String(localized: "ledger.items \(expense.items.count)"))
        }
        return Text(verbatim: parts.joined(separator: " · "))
    }
}

/// The receipt photo's thumbnail, or the category badge when there is no photo.
private struct ReceiptThumbnail: View {
    let name: String?
    let category: ExpenseCategory
    let photoStore: PhotoStore?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottomTrailing) {
                        Circle().fill(category.color).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
                    }
                    .accessibilityHidden(true)
            } else {
                CategoryBadge(category: category)
            }
        }
        .task(id: name) {
            guard let name, let photoStore else { image = nil; return }
            let cgImage = await Task.detached(priority: .utility) {
                try? photoStore.thumbnail(for: name, maxPixelSize: 120)
            }.value
            image = cgImage.map { UIImage(cgImage: $0) }
        }
    }
}
