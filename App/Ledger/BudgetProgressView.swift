import KakeiboCore
import SwiftUI

/// "Your budget" on the ledger (v1.1, B-05; visual refresh, UI-06): what is left (or over) this
/// month in large type, spent against the budget, the bar and its status in words, and for the
/// current month "Available this week". Every figure comes from `BudgetSummary` (Core); this
/// view only lays it out.
struct BudgetProgressView: View {
    let summary: BudgetSummary
    /// True for the current month: Edit, the weekly box and the alerts link. Past months are view only.
    let isCurrentMonth: Bool
    let onEdit: () -> Void
    /// Opens the budget alert settings (current month only).
    var onAlertSettings: (() -> Void)?

    var body: some View {
        if let budgetYen = summary.budgetYen, let spent = summary.spentYen, let remaining = summary.remainingYen {
            VStack(alignment: .leading, spacing: Spacing.m) {
                header
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    remainingHero(remaining)
                    spentLine(spent: spent, budgetYen: budgetYen)
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    progressBar
                    statusLabel(summary.percentSpent ?? 0)
                }
                if isCurrentMonth, let week = summary.weeklyAllowance {
                    WeeklyAllowanceBox(week: week, month: summary.month, overBudget: remaining <= 0)
                }
                Label("budget.basis", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if isCurrentMonth, let onAlertSettings {
                    Button(action: onAlertSettings) {
                        Label("budget.alertSettings", systemImage: "bell")
                    }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("budget.alertSettings")
                }
            }
        }
    }

    // MARK: Title and Edit

    private var header: some View {
        AdaptiveStack(spacing: Spacing.xs) {
            Text("budget.card.title")
                .font(.sectionTitle)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.xs)
            if isCurrentMonth {
                Button("budget.edit", action: onEdit)
                    .buttonStyle(TextButtonStyle())
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

    // MARK: Left or over

    /// "LEFT THIS MONTH ¥194,802" (past months: "SAVED"), or "OVER BUDGET BY ¥198" in vermilion.
    private func remainingHero(_ remaining: Int) -> some View {
        let over = remaining < 0
        return VStack(alignment: .leading, spacing: 2) {
            Text(over ? "budget.over" : isCurrentMonth ? "budget.left" : "budget.saved").eyebrow(uppercase: false)
            YenText(over ? -remaining : remaining)
                .font(.system(.largeTitle, weight: .semibold).monospacedDigit())
                .foregroundStyle(over ? Theme.destructive : Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        // VoiceOver: "Left this month, 194,802 yen".
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(over ? "budget.over" : "budget.left")
    }

    /// "¥5,198 spent of ¥200,000"; the budget comes last, so VoiceOver ends on it.
    private func spentLine(spent: Int, budgetYen: Int) -> some View {
        HStack(spacing: 4) {
            Text("budget.spentOf \(LedgerFormat.yen(spent))")
            YenText(budgetYen).foregroundStyle(Theme.text)
        }
        .font(.footnote.monospacedDigit())
        .foregroundStyle(Theme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("budget.value")
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

    /// The bar is clamped to full; the percentage and amounts around it are not.
    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.field)
                Capsule().fill(barColor)
                    .frame(width: proxy.size.width * (summary.progressFraction ?? 0))
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
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
        .fixedSize(horizontal: false, vertical: true)
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
            Text("budget.week.title").eyebrow(uppercase: false)
            YenText(week.yen)
                .font(.system(.title, weight: .semibold).monospacedDigit())
                .foregroundStyle(overBudget ? Theme.secondaryText : Theme.text)
                .accessibilityIdentifier("budget.week.amount")
            Text(verbatim: rangeText)
                .font(.caption.weight(.medium))
                .accessibilityIdentifier("budget.week.range")
            explanation
                .font(.caption)
        }
        .foregroundStyle(Theme.text)
        .fixedSize(horizontal: false, vertical: true)
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(overBudget ? Theme.field : Theme.accentTint,
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("budget.week")
    }

    /// "Thu, Nov 5 – Sun, Nov 8 · 4 days" / "11月5日(木)〜11月8日(日) · 4日間"; one day shows once.
    private var rangeText: String {
        let from = LedgerFormat.shortDay(week.fromDayKey)
        let through = LedgerFormat.shortDay(week.throughDayKey)
        let days = String(localized: "budget.week.days \(week.daysLeftInWeek)")
        let range = week.daysLeftInWeek == 1 ? from : String(localized: "budget.week.range \(from) \(through)")
        // English pairs the Japanese label here, as in the design ("今週使える金額 · Fri, Nov 6 – …"),
        // so the title stays short and never breaks inside the Japanese word.
        return String(localized: "budget.week.subtitle \("\(range) · \(days)")")
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
