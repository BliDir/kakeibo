import KakeiboCore
import SwiftUI

/// Budget progress in the ledger summary card (v1.1, B-05): spent against the budget, a bar,
/// what is left or over, and for the current month "Available this week".
/// Every figure comes from `BudgetSummary` (Core); this view only lays it out.
struct BudgetProgressView: View {
    let summary: BudgetSummary
    /// True for the current month: Edit and the weekly box. Past months are view only.
    let isCurrentMonth: Bool
    let onEdit: () -> Void

    var body: some View {
        if let budgetYen = summary.budgetYen, let spent = summary.spentYen, let remaining = summary.remainingYen {
            VStack(alignment: .leading, spacing: 10) {
                header(budgetYen)
                progressBar
                statusRow(spent: spent, remaining: remaining)
                if isCurrentMonth, let week = summary.weeklyAllowance {
                    WeeklyAllowanceBox(week: week, month: summary.month, overBudget: remaining <= 0)
                }
            }
        }
    }

    // MARK: Budget and Edit

    private func header(_ budgetYen: Int) -> some View {
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
            if isCurrentMonth {
                Button("budget.edit", action: onEdit)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("budget.edit")
            } else {
                Label("budget.closed", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("budget.closed")
            }
        }
    }

    // MARK: Progress

    private enum Level { case normal, near, over }

    private var level: Level {
        let percent = summary.percentSpent ?? 0
        return percent >= 100 ? .over : percent >= 80 ? .near : .normal
    }

    private var barColor: Color {
        if !isCurrentMonth { return Theme.secondaryText }
        switch level {
        case .normal: return Theme.accent
        case .near: return Theme.warning
        case .over: return Theme.destructive
        }
    }

    /// The bar is clamped to full; the percentage and amounts next to it are not.
    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.divider)
                Capsule().fill(barColor)
                    .frame(width: proxy.size.width * (summary.progressFraction ?? 0))
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func statusRow(spent: Int, remaining: Int) -> some View {
        let percent = summary.percentSpent ?? 0
        return AdaptiveStack(spacing: 8) {
            statusLabel(percent)
            Spacer(minLength: 8)
            if remaining < 0 {
                HStack(spacing: 4) {
                    Text("budget.over")
                    YenText(-remaining).font(.amountSmall.weight(.bold))
                }
                .foregroundStyle(Theme.destructive)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("budget.over")
            } else {
                HStack(spacing: 4) {
                    Text(isCurrentMonth ? "budget.left" : "budget.saved")
                    YenText(remaining).font(.amountSmall.weight(.semibold))
                }
                .foregroundStyle(Theme.text)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("budget.left")
            }
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "21% used", "82% used · close to budget", "102% used · over budget". Text, not only color.
    @ViewBuilder private func statusLabel(_ percent: Int) -> some View {
        Group {
            switch level {
            case .normal:
                if isCurrentMonth {
                    Text("budget.progress.used \(percent)").foregroundStyle(Theme.success)
                } else {
                    Label { Text("budget.progress.within \(percent)") } icon: { Image(systemName: "checkmark").accessibilityHidden(true) }
                        .foregroundStyle(Theme.success)
                }
            case .near:
                Label { Text("budget.progress.near \(percent)") } icon: { Image(systemName: "exclamationmark.triangle").accessibilityHidden(true) }
                    .foregroundStyle(Theme.warningText)
            case .over:
                Label { Text("budget.progress.over \(percent)") } icon: { Image(systemName: "exclamationmark.circle").accessibilityHidden(true) }
                    .foregroundStyle(Theme.destructive)
            }
        }
        .font(.footnote.weight(.semibold))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("budget.status")
    }
}

/// "Available this week ¥24,329 · Thu, Nov 5 – Sun, Nov 8 (4 days)", with how it is worked out.
private struct WeeklyAllowanceBox: View {
    let week: WeeklyAllowance
    let month: LedgerMonth
    let overBudget: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: 8) {
                Text("budget.week.title").font(.subheadline.weight(.bold))
                Spacer(minLength: 8)
                YenText(week.yen)
                    .font(.amount)
                    .foregroundStyle(overBudget ? Theme.secondaryText : Theme.text)
                    .accessibilityIdentifier("budget.week.amount")
            }
            Text(verbatim: rangeText)
                .font(.caption)
                .accessibilityIdentifier("budget.week.range")
            explanation
                .font(.caption)
        }
        .foregroundStyle(Theme.text)
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(overBudget ? Theme.field : Theme.accentTint, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("budget.week")
    }

    /// "Thu, Nov 5 – Sun, Nov 8 · 4 days" / "11月5日(木)〜11月8日(日) · 4日間"; one day shows once.
    private var rangeText: String {
        let from = LedgerFormat.shortDay(week.fromDayKey)
        let through = LedgerFormat.shortDay(week.throughDayKey)
        let days = String(localized: "budget.week.days \(week.daysLeftInWeek)")
        let range = week.daysLeftInWeek == 1 ? from : String(localized: "budget.week.range \(from) \(through)")
        return "\(range) · \(days)"
    }

    private var explanation: Text {
        let monthName = LedgerFormat.monthName(month)
        if overBudget {
            return Text("budget.week.usedUp \(monthName) \(LedgerFormat.shortDay(month.next.key + "-01"))")
        }
        if week.daysLeftInMonth == 1 {
            return Text("budget.week.lastDay \(monthName)")
        }
        return Text("budget.week.explain \(week.daysLeftInMonth) \(monthName)")
    }
}
