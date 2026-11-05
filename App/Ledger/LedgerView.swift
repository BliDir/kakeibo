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

    @State private var showExport = false
    @State private var budgetForm: BudgetFormItem?
    @Environment(\.isAccessibilityTextSize) private var isAccessibilityTextSize

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
        .sheet(item: $budgetForm) { item in
            BudgetSheet(form: item.form)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(month: model.month, repository: model.repository)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Header and month switcher

    private var header: some View {
        VStack(spacing: 2) {
            HStack {
                Text("ledger.overline")
                    .font(.overline).tracking(1)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button { showExport = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .foregroundStyle(Theme.accent)
                .accessibilityLabel(Text("export.button"))
                .accessibilityIdentifier("ledger.export")
                if let onShowTokens {
                    Button(action: onShowTokens) { Image(systemName: "hammer").frame(minWidth: 44, minHeight: 44) }
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityLabel(Text(verbatim: "Design tokens"))
                        .accessibilityIdentifier("debug.tokens")
                }
            }
            if isAccessibilityTextSize {
                // Huge text: the month gets the full width, the arrows go below it.
                monthTitle
                HStack { previousButton; Spacer(); nextButton }
            } else {
                HStack { previousButton; Spacer(); monthTitle; Spacer(); nextButton }
            }
        }
    }

    private var monthTitle: some View {
        VStack(spacing: 0) {
            Text(verbatim: LedgerFormat.monthTitle(model.month))
                .font(.title2.bold())
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("ledger.month")
            Text(verbatim: LedgerFormat.eraSubtitle(model.month))
                .font(.footnoteText)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var previousButton: some View {
        MonthButton(systemImage: "chevron.left", label: "ledger.month.previous", id: "ledger.previous") {
            model.showPrevious()
        }
    }

    private var nextButton: some View {
        MonthButton(systemImage: "chevron.right", label: "ledger.month.next", id: "ledger.next") {
            model.showNext()
        }
        .disabled(!model.canShowNext)
        .opacity(model.canShowNext ? 1 : 0.35)
    }

    // MARK: Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdaptiveStack(verticalAlignment: .firstTextBaseline) {
                Text("ledger.total.label").font(.overline).tracking(1).foregroundStyle(Theme.secondaryText)
                    .layoutPriority(1)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                YenText(model.summary.totalYen)
                    .font(.amountHero)
                    .foregroundStyle(Theme.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .accessibilityIdentifier("ledger.total")
            }
            AdaptiveStack {
                Text("ledger.receipts \(model.summary.count)")
                    .accessibilityIdentifier("ledger.count")
                Spacer(minLength: 8)
                Text("ledger.tax \(LedgerFormat.yen(model.summary.taxYen))")
                    .accessibilityLabel(Text("ledger.tax \(LedgerFormat.spokenYen(model.summary.taxYen))"))
            }
            .font(.footnoteText)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

            if !model.summary.categories.isEmpty {
                CategoryBar(categories: model.summary.categories)
                AdaptiveStack(spacing: 12) {
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
            budgetSection
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ledger.summary")
    }

    // MARK: Budget (v1.1)

    /// Current month: a setup prompt, or the budget with Edit. Past months: the budget, view only.
    @ViewBuilder private var budgetSection: some View {
        if let budget = model.budgetSummary {
            if let budgetYen = budget.budgetYen {
                Divider().overlay(Theme.divider)
                AdaptiveStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("budget.label").font(.overline).tracking(1).foregroundStyle(Theme.secondaryText)
                        YenText(budgetYen)
                            .font(.amount)
                            .foregroundStyle(Theme.text)
                    }
                    // VoiceOver: "BUDGET 予算, 200,000 yen".
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("budget.value")
                    Spacer(minLength: 8)
                    if model.canEditBudget {
                        Button("budget.edit") { openBudgetSheet() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("budget.edit")
                    } else {
                        Label("budget.closed", systemImage: "lock")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityIdentifier("budget.closed")
                    }
                }
            } else if model.canEditBudget {
                budgetSetupPrompt
            }
        }
    }

    private var budgetSetupPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "chart.pie")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("budget.cta.title").font(.headline).foregroundStyle(Theme.text)
                    Text("budget.cta.message").font(.footnote).foregroundStyle(Theme.text)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Button { openBudgetSheet() } label: {
                Text("budget.cta.button")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(Theme.onAccent)
            .accessibilityIdentifier("budget.cta.button")
        }
        .padding(16)
        .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("budget.cta")
    }

    private func openBudgetSheet() {
        if let form = model.makeBudgetForm() { budgetForm = BudgetFormItem(form: form) }
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

/// Previous or next month, on the ledger and the Summary tab.
struct MonthButton: View {
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
            AdaptiveStack {
                Text(verbatim: LedgerFormat.dayTitle(day.dayKey))
                Spacer(minLength: 8)
                YenText(day.subtotalYen).font(.amountSmall)
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
        AdaptiveStack(spacing: 12) {
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
                .lineLimit(2)
                if let english = expense.storeNameEn {
                    Text(verbatim: english).font(.caption).foregroundStyle(Theme.secondaryText)
                }
                details.font(.caption).foregroundStyle(Theme.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            YenText(expense.totalYen)
                .font(.amount)
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        // One element: "スターバックス, Starbucks, Dining out, Credit card, 1,078 yen, Thursday, November 5".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenLabel))
    }

    private var spokenLabel: String {
        var parts: [String] = [expense.storeName.isEmpty ? String(localized: "ledger.noStore") : expense.storeName]
        if let english = expense.storeNameEn { parts.append(english) }
        parts.append(detailParts.joined(separator: ", "))
        parts.append(LedgerFormat.spokenYen(expense.totalYen))
        parts.append(LedgerFormat.spokenDay(expense.dayKey))
        return parts.joined(separator: ", ")
    }

    /// "Groceries · IC card · 5 items".
    private var details: Text {
        Text(verbatim: detailParts.joined(separator: " · "))
    }

    private var detailParts: [String] {
        var parts = [expense.category.displayName(for: LedgerFormat.language), expense.payment.shortLabel]
        if !expense.items.isEmpty {
            parts.append(String(localized: "ledger.items \(expense.items.count)"))
        }
        return parts
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

/// The budget form presented as a sheet.
private struct BudgetFormItem: Identifiable {
    let id = UUID()
    let form: BudgetForm
}
