import KakeiboCore
import KakeiboStore
import SwiftUI

/// "Expense details" (UI-04): a saved expense, read-only, opened from a ledger row. Edit opens
/// the same form as Check and save; Delete asks first and removes the photo too.
struct ExpenseDetailView: View {
    let expense: Expense
    let services: AppServices
    let onEdit: (Expense) -> Void
    /// The expense is gone; the caller leaves this screen and shows the banner.
    let onDeleted: () -> Void

    @State private var panel: Panel?
    /// Set while deleting, so nothing reads the deleted model before the screen goes away.
    @State private var isGone = false
    @State private var showPhoto = false
    @State private var photo: UIImage?
    @Environment(\.dismiss) private var dismiss

    private enum Panel { case confirmDelete, deleteFailed }

    var body: some View {
        VStack(spacing: 0) {
            // Its own bar instead of the navigation bar: it scales with Dynamic Type, and the
            // delete panel covers it like the rest of the screen.
            TitleBar(title: "detail.title") {
                Button { dismiss() } label: {
                    Label("detail.back", systemImage: "chevron.backward")
                }
                .buttonStyle(TextButtonStyle())
                .accessibilityIdentifier("detail.back")
            } trailing: {
                Button("detail.edit") { onEdit(expense) }
                    .buttonStyle(TextButtonStyle())
                    .disabled(isGone)
                    .accessibilityIdentifier("detail.edit")
            }
            if isGone || expense.isDeleted || expense.modelContext == nil {
                Spacer()
            } else {
                content
            }
        }
        .background(Theme.groundLight.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        // A detail screen, as on the board: no tab bar under the delete panel or the content.
        .toolbar(.hidden, for: .tabBar)
        .overlay { panelView }
        .animation(.easeOut(duration: 0.2), value: panel)
        .fullScreenCover(isPresented: $showPhoto) {
            PhotoZoomView(image: photo)
        }
        .task(id: expense.photoFileName) { loadPhoto() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail")
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                hero
                facts
                if expense.photoFileName != nil {
                    ReceiptLink(image: photo, title: "review.receipt.original", subtitle: String(localized: "detail.photo.caption")) {
                        showPhoto = true
                    }
                    .accessibilityIdentifier("detail.photo")
                }
                if !expense.items.isEmpty { items }
                if let text = expense.ocrText, !text.isEmpty {
                    Card { OCRDisclosure(text: text) }
                }
                Button { panel = .confirmDelete } label: { Text("review.delete") }
                    .buttonStyle(DestructiveButtonStyle())
                    .accessibilityIdentifier("detail.delete")
            }
            .screenInset()
            .padding(.vertical, Spacing.s)
        }
    }

    // MARK: Hero

    /// Category badge, store (and its English name), the amount and the category.
    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            CategoryBadge(category: expense.category, size: 52)
            Group {
                if expense.storeName.isEmpty {
                    Text("ledger.noStore").foregroundStyle(Theme.secondaryText)
                } else {
                    Text(verbatim: expense.storeName).foregroundStyle(Theme.text)
                }
            }
            .font(.title2.weight(.bold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("detail.store")
            if let english = expense.storeNameEn {
                Text(verbatim: english).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            YenText(expense.totalYen)
                .amountDisplay(size: 40)
                .foregroundStyle(Theme.text)
                .accessibilityIdentifier("detail.amount")
            Tag(verbatim: expense.category.pairedLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Facts

    private var facts: some View {
        Card {
            FactRow(label: "review.payment", value: expense.payment.label)
            Divider().overlay(Theme.divider)
            FactRow(label: "detail.dateTime", value: dateTime)
            if let tax8 = expense.tax8Yen {
                Divider().overlay(Theme.divider)
                FactRow(label: "review.tax8", value: LedgerFormat.yen(tax8), spoken: LedgerFormat.spokenYen(tax8))
            }
            if let tax10 = expense.tax10Yen {
                Divider().overlay(Theme.divider)
                FactRow(label: "review.tax10", value: LedgerFormat.yen(tax10), spoken: LedgerFormat.spokenYen(tax10))
            }
            if let invoice = expense.invoiceNumber {
                Divider().overlay(Theme.divider)
                FactRow(label: "review.invoice", value: invoice, monospaced: true)
            }
            Divider().overlay(Theme.divider)
            FactRow(label: "detail.source", value: String(localized: expense.source == .scan ? "detail.source.scan" : "detail.source.manual"))
            if !expense.note.isEmpty {
                Divider().overlay(Theme.divider)
                FactRow(label: "review.note", value: expense.note)
            }
        }
    }

    /// "Thu, Nov 5 · 木 · 14:32", with the era date in Japanese ("令和8年11月5日").
    private var dateTime: String {
        var parts = [LedgerFormat.dayTitle(expense.dayKey)]
        if let time = expense.time { parts.append(time) }
        var text = parts.joined(separator: "  ")
        if LedgerFormat.language == .ja, let era = JapaneseEra.dateLabel(dayKey: expense.dayKey) {
            text += "\n" + era
        }
        return text
    }

    // MARK: Items

    private var items: some View {
        Card {
            DisclosureGroup {
                VStack(spacing: 0) {
                    ForEach(Array(expense.orderedItems.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Divider().overlay(Theme.divider) }
                        ItemRow(item: LineItemDraft(name: item.name, nameEn: item.nameEn,
                                                    priceYen: item.priceYen, isReducedRate: item.isReducedRate))
                    }
                }
            } label: {
                Text("review.items.count \(expense.items.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .frame(minHeight: minimumTapTarget)
                    .accessibilityIdentifier("detail.items")
            }
            .tint(Theme.accent)
        }
    }

    // MARK: Delete

    @ViewBuilder private var panelView: some View {
        switch panel {
        case .confirmDelete:
            ConfirmPanel(
                title: "confirm.delete.title",
                message: expense.photoFileName == nil ? "confirm.delete.message.noPhoto" : "confirm.delete.message",
                confirmTitle: "confirm.delete.action",
                keepTitle: "confirm.delete.keep",
                onConfirm: delete,
                onCancel: { panel = nil }
            ) {
                EntrySummary.saved(expense)
            }
        case .deleteFailed:
            FailurePanel(kind: .delete, summary: .saved(expense), onRetry: delete, onBack: { panel = nil })
        case nil:
            EmptyView()
        }
    }

    private func delete() {
        isGone = true
        do {
            try services.repository.delete(expense)
            panel = nil
            onDeleted()
        } catch {
            // The repository rolled back: the expense is still there.
            isGone = false
            panel = .deleteFailed
        }
    }

    private func loadPhoto() {
        // UIImage applies the saved EXIF orientation.
        guard let name = expense.photoFileName, let url = try? services.photoStore?.url(for: name) else {
            photo = nil
            return
        }
        photo = UIImage(contentsOfFile: url.path)
    }
}

/// "Payment ……… IC card · 交通系IC": a label and a value, stacked at the accessibility sizes.
private struct FactRow: View {
    let label: LocalizedStringKey
    let value: String
    var spoken: String?
    var monospaced = false

    var body: some View {
        AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: Spacing.xs)
            Text(verbatim: value)
                .font(monospaced ? .code : .subheadline.weight(.medium))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(Text(verbatim: spoken ?? value))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 10)
        .frame(minHeight: minimumTapTarget)
        .accessibilityElement(children: .combine)
    }
}
