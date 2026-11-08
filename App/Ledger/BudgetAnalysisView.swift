import KakeiboCore
import KakeiboStore
import SwiftUI

/// "Spending analysis" (v1.2, BI-04), opened from the ledger's insight card: the overspend (or
/// the spend so far when on pace), the month-end estimate, up to 3 drivers with their yen impact
/// and what share they explain, one suggestion each, the daily and weekly amounts for the rest
/// of the month, how it is worked out, and "Review budget" (BI-05). A closed month is read only:
/// no rest-of-month figures or suggestions, and its review opens read only. Every figure comes from
/// `LedgerModel.overspend` (Core's `OverspendAnalysis`), so it refreshes with the ledger.
struct BudgetAnalysisView: View {
    let model: LedgerModel
    /// A driver row: the ledger filtered to its category or store for the month.
    let onDriver: (InsightTarget) -> Void

    @State private var review: ReviewFormItem?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TitleBar(title: "analysis.title") {
                Button { dismiss() } label: {
                    Label("detail.back", systemImage: "chevron.backward")
                }
                .buttonStyle(TextButtonStyle())
                .accessibilityIdentifier("analysis.back")
            } trailing: {
                EmptyView()
            }
            ScrollView {
                Group {
                    if let analysis = model.overspend {
                        AnalysisContent(analysis: analysis, canReview: model.budgets != nil,
                                        onDriver: onDriver, onReview: openReview)
                    } else {
                        // The month no longer has an insight (an expense was deleted, or a new day began).
                        Text("analysis.none")
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .card()
                            .accessibilityIdentifier("analysis.none")
                    }
                }
                .screenInset()
                .padding(.vertical, Spacing.s)
            }
        }
        .background(Theme.groundLight.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $review) { item in
            BudgetReviewSheet(form: item.form).presentationDetents([.large])
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analysis.screen")
    }

    private func openReview() {
        if let form = model.makeBudgetReview() { review = ReviewFormItem(form: form) }
    }
}

/// Presents the review sheet with `.sheet(item:)`.
struct ReviewFormItem: Identifiable {
    let id = UUID()
    let form: BudgetReviewForm
}

private struct AnalysisContent: View {
    let analysis: OverspendAnalysis
    let canReview: Bool
    let onDriver: (InsightTarget) -> Void
    let onReview: () -> Void

    private var insight: BudgetInsight { analysis.insight }
    private var summary: BudgetSummary { insight.summary }
    private var isClosed: Bool { insight.state == .closedMonthOverBudget }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            header
            hero
            if !isClosed, let projected = insight.projectedYen { projection(projected) }
            if analysis.isLimitedHistory { limitedHistory }
            drivers
            if let daily = analysis.dailyAmountYen { guidance(daily: daily) }
            method
            if isClosed {
                Label("analysis.closed.note", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("analysis.closed")
                if canReview {
                    // Read only: the month's budget and what the review would have said.
                    Button(action: onReview) { Text("analysis.reviewClosed") }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                        .accessibilityIdentifier("analysis.reviewClosed")
                }
            } else if canReview {
                Button(action: onReview) { Text("analysis.review") }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("analysis.review")
            }
        }
    }

    // MARK: Header and amounts

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: LedgerFormat.monthTitle(summary.month)).eyebrow(uppercase: false)
            Group {
                if isClosed {
                    Text("analysis.headline.closed \(LedgerFormat.monthName(summary.month))")
                } else {
                    Text("analysis.headline.current")
                }
            }
            .font(.pageTitle)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            statusTag.accessibilityIdentifier("analysis.status")
        }
    }

    /// Always words, never color alone.
    @ViewBuilder private var statusTag: some View {
        switch insight.state {
        case .onPaceToOverspend: Tag("analysis.status.onPace", tone: .warning)
        case .closedMonthOverBudget: Tag("analysis.status.closed")
        default: Tag("analysis.status.over", tone: .warning)
        }
    }

    /// Over: "Over budget by ¥8,000". On pace: "Spent so far ¥82,000". Then spend against budget.
    @ViewBuilder private var hero: some View {
        if let spent = summary.spentYen, let budgetYen = summary.budgetYen {
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.isOverBudget ? "analysis.overBy" : "analysis.spentSoFar").eyebrow(uppercase: false)
                    YenText(summary.isOverBudget ? summary.overspentYen ?? 0 : spent)
                        .font(.amountHero)
                        .foregroundStyle(summary.isOverBudget ? Theme.destructive : Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("analysis.amount")
                Group {
                    if isClosed {
                        Text("analysis.finalSpend \(LedgerFormat.yen(spent)) \(LedgerFormat.yen(budgetYen))")
                            .accessibilityLabel(Text("analysis.finalSpend \(LedgerFormat.spokenYen(spent)) \(LedgerFormat.spokenYen(budgetYen))"))
                    } else {
                        Text("analysis.spentOfBudget \(LedgerFormat.yen(spent)) \(LedgerFormat.yen(budgetYen))")
                            .accessibilityLabel(Text("analysis.spentOfBudget \(LedgerFormat.spokenYen(spent)) \(LedgerFormat.spokenYen(budgetYen))"))
                    }
                }
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A labelled estimate, kept apart from the actual spend.
    private func projection(_ projected: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("analysis.projection.label").eyebrow(uppercase: false)
            Text("analysis.projection \(LedgerFormat.yen(projected))")
                .accessibilityLabel(Text("analysis.projection \(LedgerFormat.spokenYen(projected))"))
                .font(.headline.monospacedDigit())
                .foregroundStyle(Theme.text)
            Text("analysis.projection.note")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .card(padding: 18)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("analysis.projection")
    }

    private var limitedHistory: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("analysis.limited.title").font(.headline).foregroundStyle(Theme.text)
            Text("analysis.limited.message").font(.subheadline).foregroundStyle(Theme.text)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("analysis.limited")
    }

    // MARK: Drivers

    private var drivers: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(analysis.isLimitedHistory ? "analysis.drivers.limitedTitle" : "analysis.drivers.title")
                .font(.sectionTitle)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            if let explained = explainedText {
                Text(verbatim: explained)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("analysis.explained")
            }
            if !analysis.drivers.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(analysis.drivers.enumerated()), id: \.offset) { index, driver in
                        if index > 0 { Divider().overlay(Theme.divider) }
                        Button { onDriver(driver.target) } label: {
                            DriverRow(driver: driver, overBudget: analysis.isOverBudget, closed: isClosed,
                                      budgetYen: summary.budgetYen)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("analysis.driver.hint"))
                        .accessibilityIdentifier("analysis.driver")
                    }
                }
                .card(padding: Spacing.m)
            }
        }
    }

    /// "These explain 90% of the ¥8,000 overspend." The denominator is always named.
    private var explainedText: String? {
        if analysis.isLimitedHistory { return String(localized: "analysis.explained.limited") }
        if analysis.drivers.isEmpty { return String(localized: "insight.noDrivers") }
        guard let share = analysis.explainedShare, let basis = analysis.basisYen else { return nil }
        let percent = Int((share * 100).rounded(.down))
        return analysis.isOverBudget
            ? String(localized: "analysis.explained.over \(percent) \(LedgerFormat.yen(basis))")
            : String(localized: "analysis.explained.onPace \(percent) \(LedgerFormat.yen(basis))")
    }

    // MARK: Rest of the month

    private func guidance(daily: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("analysis.guidance.title").font(.headline).foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            AdaptiveStack(verticalAlignment: .top, spacing: Spacing.m) {
                metric("analysis.guidance.daily", daily, id: "analysis.daily")
                if let weekly = analysis.weeklyAmountYen {
                    metric("analysis.guidance.weekly", weekly, id: "analysis.weekly")
                }
            }
            Text(verbatim: guidanceNote)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analysis.guidance")
    }

    private func metric(_ label: LocalizedStringKey, _ yen: Int, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Theme.secondaryText)
            YenText(yen)
                .font(.system(.title2, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.text)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private var guidanceNote: String {
        if summary.isOverBudget { return String(localized: "analysis.guidance.over") }
        let remaining = summary.remainingYen ?? 0
        var note = String(localized: "analysis.guidance.left \(LedgerFormat.yen(remaining))")
        if let week = summary.weeklyAllowance {
            note = String(localized: "analysis.guidance.leftDays \(LedgerFormat.yen(remaining)) \(week.daysLeftInMonth) \(week.daysLeftInWeek)")
        }
        return note + " " + String(localized: "analysis.guidance.guide")
    }

    // MARK: How it is worked out

    private var method: some View {
        DisclosureGroup {
            Text(verbatim: methodText)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Spacing.xs)
        } label: {
            Text("analysis.method.title")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(minHeight: minimumTapTarget)
                .accessibilityIdentifier("analysis.method")
        }
        .tint(Theme.accent)
    }

    private var methodText: String {
        var parts: [String] = []
        if let comparison = insight.comparison, !comparison.baseline.isLimitedHistory {
            let months = InsightWording.months(comparison.baseline.months)
            parts.append(isClosed
                ? String(localized: "analysis.method.closed \(months)")
                : String(localized: "analysis.method.current \(months) \(comparison.pace.elapsedDays) \(comparison.pace.daysInMonth)"))
        } else {
            parts.append(String(localized: "analysis.method.limited"))
        }
        if !isClosed, insight.projectedYen == nil {
            parts.append(String(localized: "analysis.method.projectionLater \(MonthPace.projectionStartDay)"))
        }
        parts.append(String(localized: "analysis.method.common"))
        return parts.joined(separator: " ")
    }
}

/// One driver: name and kind, the yen impact, what happened and (current month) what would help.
/// VoiceOver reads it as full sentences.
private struct DriverRow: View {
    let driver: OverspendDriver
    let overBudget: Bool
    let closed: Bool
    let budgetYen: Int?

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 4) {
                AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: Spacing.xs) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: InsightWording.name(driver.target))
                            .font(.bodyEmphasis)
                            .foregroundStyle(Theme.text)
                        Text(verbatim: InsightWording.kind(driver.kind))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: Spacing.xs)
                    Text(verbatim: InsightWording.impact(driver))
                        .font(.amount)
                        .foregroundStyle(Theme.text)
                }
                Text(verbatim: InsightWording.description(driver, closed: closed, budgetYen: budgetYen))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                if let suggestion = InsightWording.suggestion(driver, overBudget: overBudget, closed: closed) {
                    Label {
                        Text(verbatim: suggestion)
                    } icon: {
                        Image(systemName: "lightbulb").accessibilityHidden(true)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.s)
        .frame(minHeight: minimumTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: InsightWording.spoken(driver, overBudget: overBudget, closed: closed,
                                                                 budgetYen: budgetYen)))
    }
}
