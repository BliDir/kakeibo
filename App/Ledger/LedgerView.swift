import KakeiboCore
import KakeiboScan
import KakeiboStore
import SwiftUI

/// The ledger home screen (visual refresh, UI-02): the month's total at a glance, the three
/// ways to add an expense, the top category, the budget, and the month's activity by day.
struct LedgerView: View {
    let model: LedgerModel
    let session: ScanSession
    let photoStore: PhotoStore?
    let onSelect: (Expense) -> Void
    let onManual: () -> Void
    /// Debug builds only: opens the design system gallery.
    var onShowTokens: (() -> Void)?

    @State private var showExport = false
    @State private var budgetForm: BudgetFormItem?
    @Environment(\.isAccessibilityTextSize) private var isAccessibilityTextSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                toolbar
                monthSwitcher
                hero
                ScanEntryButtons(session: session, onManual: onManual)
                if model.isEmpty {
                    emptyState
                } else {
                    insight
                }
                budgetSection
                if !model.isEmpty { activity }
                if model.loadFailed {
                    Text("ledger.loadFailed").font(.caption).foregroundStyle(Theme.destructive)
                }
            }
            .screenInset()
            .padding(.top, Spacing.xs)
            .padding(.bottom, Spacing.l)
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

    // MARK: Toolbar and month switcher

    /// The wordmark, export and (Debug) the design system gallery.
    private var toolbar: some View {
        HStack(spacing: Spacing.xs) {
            BrandLogo(maxWidth: 112)
                .frame(maxHeight: 32, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.xs)
            Button { showExport = true } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(TextButtonStyle())
            .accessibilityLabel(Text("export.button"))
            .accessibilityIdentifier("ledger.export")
            if let onShowTokens {
                Button(action: onShowTokens) { Image(systemName: "hammer") }
                    .buttonStyle(TextButtonStyle())
                    .accessibilityLabel(Text(verbatim: "Design system"))
                    .accessibilityIdentifier("debug.tokens")
            }
        }
    }

    private var monthSwitcher: some View {
        Group {
            if isAccessibilityTextSize {
                // Huge text: the month gets the full width, the arrows go below it.
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    monthTitle.frame(maxWidth: .infinity)
                    HStack { previousButton; Spacer(); nextButton }
                }
            } else {
                HStack(spacing: Spacing.s) { previousButton; Spacer(minLength: 0); monthTitle; Spacer(minLength: 0); nextButton }
            }
        }
    }

    /// "November 2026" over "令和8年11月 · Reiwa 8", in a soft pill.
    private var monthTitle: some View {
        VStack(spacing: 0) {
            Text(verbatim: LedgerFormat.monthTitle(model.month))
                .font(.headline)
                .foregroundStyle(Theme.text)
                .accessibilityIdentifier("ledger.month")
            Text(verbatim: LedgerFormat.eraSubtitle(model.month))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 6)
        .frame(maxWidth: isAccessibilityTextSize ? .infinity : nil)
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(Theme.border))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var previousButton: some View {
        MonthButton(systemImage: "chevron.left", label: "ledger.month.previous", id: "ledger.previous") {
            model.showPrevious()
        }
    }

    private var nextButton: some View {
        // No future months: disabled on the current month.
        MonthButton(systemImage: "chevron.right", label: "ledger.month.next", id: "ledger.next") {
            model.showNext()
        }
        .disabled(!model.canShowNext)
    }

    // MARK: Hero

    /// "合計 TOTAL", the month's total, and "4 receipts · Tax ¥259".
    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("ledger.total.label").eyebrow()
            HeroAmount(amount: model.summary.totalYen)
                .accessibilityIdentifier("ledger.total")
            AdaptiveStack(spacing: Spacing.xs) {
                Text("ledger.receipts \(model.summary.count)")
                    .accessibilityIdentifier("ledger.count")
                if !isAccessibilityTextSize {
                    Text(verbatim: "·").accessibilityHidden(true)
                }
                Text("ledger.tax \(LedgerFormat.yen(model.summary.taxYen))")
                    .accessibilityLabel(Text("ledger.tax \(LedgerFormat.spokenYen(model.summary.taxYen))"))
            }
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ledger.summary")
    }

    // MARK: Insight

    /// The biggest category ("Most spent on Groceries · ¥1,310 · 25%"), with the month's split.
    @ViewBuilder private var insight: some View {
        if let top = model.summary.categories.first {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .top, spacing: Spacing.s) {
                    CategoryBadge(category: top.category, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ledger.insight.title \(top.category.displayName(for: LedgerFormat.language))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Text("ledger.insight.detail \(LedgerFormat.yen(top.totalYen)) \(Int((top.share * 100).rounded()))")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: insightSpoken(top)))
                CategoryBar(categories: model.summary.categories)
                FlowLegend(categories: Array(model.summary.categories.prefix(4)))
            }
            .card(padding: 18)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ledger.insight")
        }
    }

    private func insightSpoken(_ top: MonthSummary.CategoryTotal) -> String {
        let name = top.category.displayName(for: LedgerFormat.language)
        let percent = Int((top.share * 100).rounded())
        return String(localized: "ledger.insight.title \(name)") + ". "
            + String(localized: "ledger.insight.detail \(LedgerFormat.spokenYen(top.totalYen)) \(percent)")
    }

    // MARK: Budget (v1.1)

    /// Current month: a setup prompt, or the budget with Edit. Past months: the budget, view only.
    @ViewBuilder private var budgetSection: some View {
        if let budget = model.budgetSummary {
            if budget.budgetYen != nil {
                BudgetProgressView(summary: budget, isCurrentMonth: model.canEditBudget, onEdit: openBudgetSheet)
                    .card(padding: 18)
            } else if model.canEditBudget {
                budgetSetupPrompt
            }
        }
    }

    private var budgetSetupPrompt: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .top, spacing: Spacing.s) {
                Image(systemName: "chart.pie")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.groundLight, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("budget.cta.title").font(.headline).foregroundStyle(Theme.text)
                    Text("budget.cta.message").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Button { openBudgetSheet() } label: {
                Text("budget.cta.button")
            }
            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
            .accessibilityIdentifier("budget.cta.button")
        }
        .card(padding: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("budget.cta")
    }

    private func openBudgetSheet() {
        if let form = model.makeBudgetForm() { budgetForm = BudgetFormItem(form: form) }
    }

    // MARK: Activity

    private var activity: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            AdaptiveStack(spacing: Spacing.xs) {
                Text("ledger.activity")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Tag(verbatim: LedgerFormat.monthName(model.month))
                    .accessibilityHidden(true)
            }
            ForEach(model.days, id: \.dayKey) { day in
                DaySection(day: day, photoStore: photoStore, onSelect: onSelect)
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 64, height: 64)
                .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
            Text("ledger.empty.title")
                .font(.sectionTitle)
                .foregroundStyle(Theme.text)
            Text("ledger.empty.message")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Text("ledger.empty.footnote")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.l)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ledger.empty")
    }
}

/// The month's total, large: a smaller ¥ before the digits in English, a smaller 円 after them
/// in Japanese. One text element; VoiceOver reads "5,198 yen" / "5,198円".
struct HeroAmount: View {
    let amount: Int
    @ScaledMetric(relativeTo: .largeTitle) private var digitsSize: CGFloat = 52
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 28

    var body: some View {
        let (symbol, digits, prefix) = Self.parts(of: amount)
        let symbolText = Text(verbatim: symbol)
            .font(.system(size: symbolSize, weight: .medium))
            .foregroundStyle(Theme.secondaryText)
        let digitsText = Text(verbatim: digits)
            .font(.system(size: digitsSize, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.text)
        (prefix ? symbolText + digitsText : digitsText + symbolText)
            .tracking(-digitsSize * 0.03)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .accessibilityLabel(Text(verbatim: LedgerFormat.spokenYen(amount)))
    }

    /// Splits "¥5,198", "-¥120" or "5,198円" into the symbol and the rest.
    static func parts(of amount: Int) -> (symbol: String, digits: String, symbolFirst: Bool) {
        let text = LedgerFormat.yen(amount)
        if text.hasSuffix("円") { return ("円", String(text.dropLast()), false) }
        guard let index = text.firstIndex(of: "¥") else { return ("", text, true) }
        let sign = String(text[..<index])
        return ("¥", sign + String(text[text.index(after: index)...]), true)
    }
}

/// Previous or next month, on the ledger and the Summary tab. Disabled: no future months.
struct MonthButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let id: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: minimumTapTarget, height: minimumTapTarget)
                .background(Theme.secondaryFillOpaque, in: Circle())
                .overlay(Circle().stroke(Theme.secondaryBorder))
                .foregroundStyle(isEnabled ? Theme.text : Theme.pending)
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
            HStack(spacing: 3) {
                ForEach(categories, id: \.category) { entry in
                    entry.category.color
                        .frame(width: max(2, (proxy.size.width - CGFloat(categories.count - 1) * 3) * entry.share))
                }
            }
        }
        .frame(height: 7)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// Category dots and names that wrap onto more lines when they do not fit.
private struct FlowLegend: View {
    let categories: [MonthSummary.CategoryTotal]

    var body: some View {
        WrapLayout(spacing: Spacing.s, lineSpacing: 4) {
            ForEach(categories, id: \.category) { entry in
                HStack(spacing: 6) {
                    Circle().fill(entry.category.color).frame(width: 8, height: 8)
                    Text(verbatim: entry.category.displayName(for: LedgerFormat.language))
                }
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.secondaryText)
        .accessibilityHidden(true)
    }
}

/// Lays children out left to right and starts a new line when the next one does not fit.
struct WrapLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// One day: its date and subtotal ("FRI, NOV 6 · 金   ¥2,388"), then its expenses.
private struct DaySection: View {
    let day: DayGroup<Expense>
    let photoStore: PhotoStore?
    let onSelect: (Expense) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            AdaptiveStack {
                Text(verbatim: LedgerFormat.dayTitle(day.dayKey))
                Spacer(minLength: Spacing.xs)
                YenText(day.subtotalYen)
                    .monospacedDigit()
            }
            .eyebrow()
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(day.items, id: \.id) { expense in
                Button { onSelect(expense) } label: {
                    LedgerRow(expense: expense, photoStore: photoStore)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ledger.row")
            }
        }
    }
}

/// Thumbnail or category badge, store, category · payment · items, amount.
private struct LedgerRow: View {
    let expense: Expense
    let photoStore: PhotoStore?

    var body: some View {
        AdaptiveStack(spacing: Spacing.s) {
            ReceiptThumbnail(name: expense.photoFileName, category: expense.category, photoStore: photoStore)
            VStack(alignment: .leading, spacing: 1) {
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
        .padding(.vertical, Spacing.s)
        .frame(minHeight: 60)
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

    private let size: CGFloat = 46

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Circle().fill(category.color).frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Theme.groundLight, lineWidth: 2))
                    }
                    .accessibilityHidden(true)
            } else {
                CategoryBadge(category: category, size: size)
            }
        }
        .task(id: name) {
            guard let name, let photoStore else { image = nil; return }
            let cgImage = await Task.detached(priority: .utility) {
                try? photoStore.thumbnail(for: name, maxPixelSize: 140)
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
