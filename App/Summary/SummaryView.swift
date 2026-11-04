import Charts
import KakeiboCore
import KakeiboStore
import SwiftUI

/// The Summary tab: where the month's money went. Shares `LedgerModel` with the ledger,
/// so both tabs show the same month and update after any save or delete.
struct SummaryView: View {
    let model: LedgerModel

    @State private var showExport = false
    @Environment(\.isAccessibilityTextSize) private var isAccessibilityTextSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                totalCard
                categoryCard
                if model.loadFailed {
                    Text("ledger.loadFailed").font(.caption).foregroundStyle(Theme.destructive)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.groundLight.ignoresSafeArea())
        .sheet(isPresented: $showExport) {
            ExportSheet(month: model.month, repository: model.repository)
                .presentationDetents([.medium, .large])
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("summary")
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: LedgerFormat.eraSubtitle(model.month))
                        .font(.overline).tracking(1)
                        .foregroundStyle(Theme.secondaryText)
                    Text("summary.title \(LedgerFormat.monthTitle(model.month))")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.text)
                        .accessibilityIdentifier("summary.month")
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { showExport = true } label: {
                    Image(systemName: "square.and.arrow.up").frame(minWidth: 44, minHeight: 44)
                }
                .foregroundStyle(Theme.accent)
                .accessibilityLabel(Text("export.button"))
                .accessibilityIdentifier("summary.export")
            }
            HStack {
                MonthButton(systemImage: "chevron.left", label: "ledger.month.previous", id: "summary.previous") {
                    model.showPrevious()
                }
                Spacer()
                MonthButton(systemImage: "chevron.right", label: "ledger.month.next", id: "summary.next") {
                    model.showNext()
                }
                .disabled(!model.canShowNext)
                .opacity(model.canShowNext ? 1 : 0.35)
            }
        }
    }

    // MARK: Total, comparison, tax

    private var totalCard: some View {
        let summary = model.summary
        return VStack(alignment: .leading, spacing: 10) {
            AdaptiveStack(verticalAlignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ledger.total.label")
                    Text("ledger.receipts \(summary.count)").accessibilityIdentifier("summary.count")
                }
                .font(.overline).tracking(1)
                .foregroundStyle(Theme.secondaryText)
                .layoutPriority(1)
                Spacer(minLength: 8)
                YenText(summary.totalYen)
                    .font(.amountHero)
                    .foregroundStyle(Theme.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .accessibilityIdentifier("summary.total")
            }
            if model.previousSummary.count > 0 { comparisonRow }
            Divider().overlay(Theme.divider)
            // One line when it fits; stacked at large text sizes instead of breaking words.
            Group {
                if isAccessibilityTextSize {
                    taxColumn(summary)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            taxItem(Text("summary.tax"), summary.taxYen)
                            Spacer(minLength: 4)
                            taxItem(Text(verbatim: "8%"), summary.tax8Yen)
                            Spacer(minLength: 4)
                            taxItem(Text(verbatim: "10%"), summary.tax10Yen)
                        }
                        taxColumn(summary)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("summary.tax")
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    /// "October ¥178,180" and "↑ +¥8,240 (4.6%)".
    private var comparisonRow: some View {
        let comparison = model.comparison
        let previousName = LedgerFormat.monthName(model.month.previous)
        let difference = LedgerFormat.spokenYen(abs(comparison.differenceYen))
        return AdaptiveStack {
            Text(verbatim: "\(previousName) \(LedgerFormat.yen(comparison.previousYen))")
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Image(systemName: comparison.direction == .down ? "arrow.down" : comparison.direction == .up ? "arrow.up" : "equal")
                    .font(.caption.weight(.bold))
                Text(verbatim: changeText(comparison))
                    .font(.amountSmall)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(comparison.direction == .up ? Theme.warningText : comparison.direction == .down ? Theme.success : Theme.secondaryText)
        }
        .font(.footnoteText)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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

    private func taxColumn(_ summary: MonthSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            taxItem(Text("summary.tax"), summary.taxYen)
            AdaptiveStack(spacing: 16) {
                taxItem(Text(verbatim: "8%"), summary.tax8Yen)
                taxItem(Text(verbatim: "10%"), summary.tax10Yen)
            }
        }
    }

    private func taxItem(_ label: Text, _ yen: Int) -> some View {
        HStack(spacing: 4) {
            label
            YenText(yen).font(.amountSmall).foregroundStyle(Theme.text)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: By category

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("summary.byCategory")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityAddTraits(.isHeader)
            if model.summary.categories.isEmpty {
                Text("summary.empty")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .accessibilityIdentifier("summary.empty")
            } else {
                ForEach(model.summary.categories, id: \.category) { entry in
                    CategoryRow(entry: entry)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// One category: names (ja and en) and share, its bar, and the amount.
private struct CategoryRow: View {
    let entry: MonthSummary.CategoryTotal
    @Environment(\.isAccessibilityTextSize) private var isAccessibilityTextSize

    var body: some View {
        let language = LedgerFormat.language
        let primary = entry.category.displayName(for: language)
        let secondary = entry.category.displayName(for: language == .ja ? .en : .ja)
        let share = entry.share.formatted(.percent.precision(.fractionLength(1)))
        let amount = LedgerFormat.yen(entry.totalYen)

        AdaptiveStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: primary).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                Text(verbatim: "\(secondary) · \(share)").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: isAccessibilityTextSize ? nil : 112, alignment: .leading)
            CategoryBarChart(entry: entry)
            Text(verbatim: amount)
                .font(.amountSmall)
                .foregroundStyle(Theme.text)
                .frame(minWidth: isAccessibilityTextSize ? nil : 76, alignment: .trailing)
        }
        .padding(.vertical, 8)
        // VoiceOver reads "Groceries, 食料品: ¥72,380, 38.8%".
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
                height: .fixed(10)
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
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}
