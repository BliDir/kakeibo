import Charts
import KakeiboCore
import KakeiboStore
import SwiftUI

/// The Summary tab (visual refresh, UI-05): where the month's money went. Shares `LedgerModel`
/// with the ledger, so both tabs show the same month and update after any save or delete.
/// Every number comes from `MonthSummary` / `MonthComparison`; this view only lays them out.
struct SummaryView: View {
    let model: LedgerModel

    @State private var showExport = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                ScreenHeader("tab.summary") {
                    Button { showExport = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(TextButtonStyle())
                    .accessibilityLabel(Text("export.button"))
                    .accessibilityIdentifier("summary.export")
                }
                MonthSwitcher(model: model, idPrefix: "summary")
                hero
                categoryCard
                statsCard
                Text("summary.note")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button { showExport = true } label: {
                    Label("summary.exportMonth", systemImage: "tablecells")
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("summary.exportMonth")
                if model.loadFailed {
                    Text("ledger.loadFailed").font(.caption).foregroundStyle(Theme.destructive)
                }
            }
            .screenInset()
            .padding(.top, Spacing.xs)
            .padding(.bottom, Spacing.l)
        }
        .background(Theme.groundLight.ignoresSafeArea())
        .sheet(isPresented: $showExport) {
            ExportSheet(month: model.month, repository: model.repository)
                .presentationDetents([.large])
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("summary")
    }

    // MARK: Hero: total and month-over-month

    /// "RECORDED SPENDING", the month's total, and the change from last month.
    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("summary.recorded").eyebrow()
            HeroAmount(amount: model.summary.totalYen)
                .accessibilityIdentifier("summary.total")
            if model.previousSummary.count > 0 { comparisonRow }
        }
    }

    /// "↑ +¥8,240 (4.6%)" and "October ¥178,180".
    private var comparisonRow: some View {
        let comparison = model.comparison
        let previousName = LedgerFormat.monthName(model.month.previous)
        let difference = LedgerFormat.spokenYen(abs(comparison.differenceYen))
        return AdaptiveStack(spacing: Spacing.xs) {
            HStack(spacing: 4) {
                Image(systemName: comparison.direction == .down ? "arrow.down" : comparison.direction == .up ? "arrow.up" : "equal")
                    .font(.caption.weight(.bold))
                Text(verbatim: changeText(comparison))
                    .font(.amountSmall.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(comparison.direction == .up ? Theme.warningText : comparison.direction == .down ? Theme.success : Theme.secondaryText)
            Text(verbatim: "\(previousName) \(LedgerFormat.yen(comparison.previousYen))")
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnoteText)
        .frame(maxWidth: .infinity, minHeight: minimumTapTarget, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(comparisonLabel(comparison.direction, difference: difference, month: previousName))
        .accessibilityIdentifier("summary.comparison")
    }

    private func changeText(_ comparison: MonthComparison) -> String {
        let sign = comparison.differenceYen > 0 ? "+" : ""
        let amount = sign + LedgerFormat.yen(comparison.differenceYen)
        guard let change = comparison.change else { return amount }
        return "\(amount) (\(abs(change).formatted(.percent.precision(.fractionLength(1)))))"
    }

    private func comparisonLabel(_ direction: MonthComparison.Direction, difference: String, month: String) -> Text {
        switch direction {
        case .up: Text("summary.change.up \(difference) \(month)")
        case .down: Text("summary.change.down \(difference) \(month)")
        case .same: Text("summary.change.same \(month)")
        }
    }

    // MARK: By category

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text("summary.byCategory")
                    .font(.sectionTitle)
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if !model.summary.categories.isEmpty {
                    Text("summary.byCategory.columns")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            if model.summary.categories.isEmpty {
                Text("summary.empty")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.l)
                    .accessibilityIdentifier("summary.empty")
            } else {
                VStack(spacing: Spacing.m) {
                    ForEach(model.summary.categories, id: \.category) { entry in
                        CategoryRow(entry: entry)
                    }
                }
            }
        }
        .card()
    }

    // MARK: Receipts and tax

    /// "RECEIPTS 4" beside "TAX INCL. ¥259", with the 8% and 10% split under it.
    private var statsCard: some View {
        let summary = model.summary
        return AdaptiveStack(verticalAlignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text("summary.receipts").eyebrow()
                Text(verbatim: "\(summary.count)")
                    .font(.title.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // One element: "4 receipts".
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("ledger.receipts \(summary.count)"))
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier("summary.count")

            VStack(alignment: .leading, spacing: 4) {
                Text("summary.tax").eyebrow()
                YenText(summary.taxYen)
                    .font(.title.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.text)
                AdaptiveStack(spacing: Spacing.s) {
                    taxItem(Text(verbatim: "8%"), summary.tax8Yen)
                    taxItem(Text(verbatim: "10%"), summary.tax10Yen)
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("summary.tax")
        }
        .card()
    }

    private func taxItem(_ label: Text, _ yen: Int) -> some View {
        HStack(spacing: 4) {
            label
            YenText(yen).font(.amountSmall).foregroundStyle(Theme.text)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One category: its name and amount, its bar in the category's color, then the other
/// language's name and the share ("食料品 · 38.8%").
private struct CategoryRow: View {
    let entry: MonthSummary.CategoryTotal

    var body: some View {
        let language = LedgerFormat.language
        let primary = entry.category.displayName(for: language)
        let secondary = entry.category.displayName(for: language == .ja ? .en : .ja)
        let share = entry.share.formatted(.percent.precision(.fractionLength(1)))

        VStack(alignment: .leading, spacing: 6) {
            AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Circle().fill(entry.category.color).frame(width: 10, height: 10)
                    Text(verbatim: primary).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                }
                Spacer(minLength: Spacing.xs)
                Text(verbatim: LedgerFormat.yen(entry.totalYen))
                    .font(.amount)
                    .foregroundStyle(Theme.text)
            }
            CategoryBarChart(entry: entry)
            Text(verbatim: "\(secondary) · \(share)")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        // VoiceOver reads "Groceries, 食料品: 72,380 yen, 38.8%".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(primary), \(secondary)"))
        .accessibilityValue(Text(verbatim: "\(LedgerFormat.spokenYen(entry.totalYen)), \(share)"))
        .accessibilityIdentifier("summary.category.\(entry.category.rawValue)")
    }
}

/// The category's bar, scaled so the largest category fills the track.
private struct CategoryBarChart: View {
    let entry: MonthSummary.CategoryTotal

    private static let startLabel = "start"
    private static let lengthLabel = "length"
    private static let categoryLabel = "category"

    var body: some View {
        Chart {
            // Plain strings: the chart is hidden from VoiceOver (the row reads it), so these
            // labels are never shown and must not land in the String Catalog.
            BarMark(
                xStart: .value(Self.startLabel, 0),
                xEnd: .value(Self.lengthLabel, max(entry.barFraction, 0.02)),
                y: .value(Self.categoryLabel, entry.category.rawValue),
                height: .fixed(8)
            )
            .foregroundStyle(entry.category.color)
            .clipShape(Capsule())
        }
        .chartXScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.background(Theme.field, in: Capsule())
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}
