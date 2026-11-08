import KakeiboCore
import SwiftUI

/// The ledger's insight card (v1.2, BI-04), under "Your budget": "Heads up" when the month is on
/// pace to go over, "Why am I over?" when it is over, and for a closed month that went over, a
/// look back. Headline, the top driver and "See analysis". Figures come from `OverspendAnalysis`.
/// Text on the green tint is always `Theme.text`, the contrast-checked pair.
///
/// BI-06: where the on-device model wrote a sentence that passed `InsightSentenceCheck`, it
/// replaces the top driver's template sentence; otherwise the template is shown.
struct BudgetInsightCard: View {
    let analysis: OverspendAnalysis
    /// A checked model sentence for this analysis, or nil for the template.
    var modelSentence: String? = nil
    let onSeeAnalysis: () -> Void

    private var state: BudgetInsight.State { analysis.insight.state }
    private var isClosed: Bool { state == .closedMonthOverBudget }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label { title } icon: {
                    Image(systemName: state == .onPaceToOverspend ? "exclamationmark.triangle" : "magnifyingglass")
                        .accessibilityHidden(true)
                }
                .font(.headline)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
                if state == .onPaceToOverspend, let projected = analysis.insight.projectedYen {
                    Text("insight.card.projection \(LedgerFormat.yen(projected))")
                        .accessibilityLabel(Text("insight.card.projection \(LedgerFormat.spokenYen(projected))"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.text)
                }
                if analysis.isLimitedHistory {
                    Text("insight.card.limited")
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                } else if let top = analysis.drivers.first {
                    Text(verbatim: modelSentence
                        ?? InsightWording.description(top, closed: isClosed, budgetYen: analysis.insight.summary.budgetYen))
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                } else {
                    Text("insight.noDrivers")
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)

            Button(action: onSeeAnalysis) {
                Label("insight.card.see", systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(TextButtonStyle())
            .accessibilityIdentifier("insight.see")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insight.card")
    }

    @ViewBuilder private var title: some View {
        switch state {
        case .onPaceToOverspend: Text("insight.card.onPace.title")
        case .closedMonthOverBudget: Text("insight.card.closed.title \(LedgerFormat.monthName(analysis.insight.summary.month))")
        default: Text("insight.card.over.title")
        }
    }
}

/// Text first, then the icon ("See analysis →").
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon.accessibilityHidden(true)
        }
    }
}
