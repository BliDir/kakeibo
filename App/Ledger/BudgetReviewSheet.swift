import KakeiboCore
import KakeiboStore
import SwiftUI

/// "Review budget" (v1.2, BI-05), opened from the analysis: the current and suggested budget,
/// BI-03's recommendation with its reason, the new amount, the three choices (keep, this month
/// only, from this month on) and what the chosen one means for the rest of the month. Nothing is
/// stored until Confirm. A closed month opens read only. Logic is in `BudgetReviewForm`; this
/// view only binds to it, and every sentence comes from `InsightWording`.
struct BudgetReviewSheet: View {
    @Bindable var form: BudgetReviewForm
    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFocused: Bool

    private var review: BudgetReview { form.review }
    private var monthName: String { LedgerFormat.monthName(form.month) }

    var body: some View {
        VStack(spacing: 0) {
            TitleBar(title: "budgetReview.title") {
                Button(form.isReadOnly ? "budgetReview.close" : "budgetReview.cancel") { dismiss() }
                    .buttonStyle(TextButtonStyle())
                    .accessibilityIdentifier("budgetReview.cancel")
            } trailing: {
                EmptyView()
            }
            .background(Theme.groundLight)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    intro
                    recommendationCard
                    if form.isReadOnly {
                        Label {
                            Text("budgetReview.closed.note \(monthName)")
                        } icon: {
                            Image(systemName: "lock").accessibilityHidden(true)
                        }
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("budgetReview.closed")
                    } else {
                        amountCard
                        choicesCard
                        previewCard
                    }
                }
                .screenInset()
                .padding(.vertical, Spacing.s)
            }
            .scrollDismissesKeyboard(.interactively)
            if !form.isReadOnly { confirmBar }
        }
        .background(Theme.groundLight.ignoresSafeArea())
        // VoiceOver users are typing in the field and would not hear the error appear under it.
        .onChange(of: form.problem) { _, problem in
            if let problem { AccessibilityNotification.Announcement(InsightWording.problem(problem)).post() }
        }
        .onChange(of: form.choice) { _, choice in
            if choice == .keep { amountFocused = false }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("budgetReview.sheet")
    }

    // MARK: Recommendation

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: LedgerFormat.monthTitle(form.month)).eyebrow()
            Group {
                if form.isReadOnly {
                    Text("budgetReview.headline.closed \(monthName)")
                } else {
                    Text("budgetReview.headline \(monthName)")
                }
            }
            .font(.pageTitle)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        }
    }

    /// The recommendation in words (never color alone), its reason, and current against suggested.
    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Tag(verbatim: InsightWording.recommendationTitle(review),
                tone: form.hasSuggestion && !isKeep ? .warning : .accent)
                .accessibilityIdentifier("budgetReview.recommendation")
            Text(verbatim: InsightWording.recommendationReason(review))
                .font(.subheadline)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("budgetReview.reason")
            VStack(spacing: Spacing.xs) {
                if let current = review.currentBudget.yen {
                    amountRow("budgetReview.current", current, id: "budgetReview.currentAmount")
                }
                if let suggested = review.suggested.yen {
                    amountRow("budgetReview.suggested", suggested, id: "budgetReview.suggestedAmount")
                }
            }
            if let basis = InsightWording.suggestedBasis(review) {
                Text(verbatim: basis)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("budgetReview.summary")
    }

    private var isKeep: Bool {
        if case .keep = review.recommendation { true } else { false }
    }

    private func amountRow(_ label: LocalizedStringKey, _ yen: Int, id: String) -> some View {
        AdaptiveStack(spacing: Spacing.xs) {
            Text(label).font(.subheadline).foregroundStyle(Theme.secondaryText)
            Spacer(minLength: Spacing.xs)
            YenText(yen).font(.amount).foregroundStyle(Theme.text)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    // MARK: Amount

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("budgetReview.amount.label").eyebrow(uppercase: false)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                let symbol = Yen.fieldSymbol(for: LedgerFormat.language)
                if symbol.isPrefix { Text(verbatim: symbol.symbol).font(.amountHero).foregroundStyle(Theme.secondaryText) }
                TextField(text: $form.amountText, prompt: Text(verbatim: "0")) { Text("budgetReview.amount.label") }
                    .font(.amountHero)
                    .foregroundStyle(form.isAmountEditable ? Theme.text : Theme.secondaryText)
                    .keyboardType(.numberPad)
                    .focused($amountFocused)
                    .disabled(!form.isAmountEditable)
                    .accessibilityIdentifier("budgetReview.amount")
                if !symbol.isPrefix { Text(verbatim: symbol.symbol).font(.title.weight(.semibold)).foregroundStyle(Theme.secondaryText) }
            }
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(form.problem != nil ? Theme.destructive : form.isAmountEditable ? Theme.accent : Theme.border)
                    .frame(height: 2)
            }
            if let problem = form.problem {
                Label(InsightWording.problem(problem), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("budgetReview.problem")
            }
            if !form.isAmountEditable {
                Text("budgetReview.amount.keepHint")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    // MARK: Choices

    private var choicesCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("budgetReview.scope.title")
                .font(.sectionTitle)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(BudgetReview.Choice.allCases.enumerated()), id: \.offset) { index, choice in
                    if index > 0 { Divider().overlay(Theme.divider) }
                    ReviewChoiceRow(title: InsightWording.choiceTitle(choice),
                                    detail: InsightWording.choiceDetail(choice, review: review),
                                    selected: form.choice == choice,
                                    id: InsightWording.choiceID(choice)) { form.choice = choice }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, 4)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: Preview

    /// Remaining (or still over), per day and this week, for the chosen option. Recomputed as the
    /// choice or amount changes; nothing is stored.
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("budgetReview.preview.title").font(.headline).foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            if let preview = form.preview {
                let week = review.analysis.insight.summary.weeklyAllowance
                VStack(spacing: Spacing.xs) {
                    if preview.remainingYen < 0 {
                        previewRow(Text("budgetReview.preview.over"), -preview.remainingYen, id: "budgetReview.preview.remaining")
                    } else {
                        previewRow(Text("budgetReview.preview.remaining"), preview.remainingYen, id: "budgetReview.preview.remaining")
                    }
                    if let daily = preview.dailyAmountYen {
                        previewRow(week.map { Text("budgetReview.preview.daily \($0.daysLeftInMonth)") } ?? Text("analysis.guidance.daily"),
                                   daily, id: "budgetReview.preview.daily")
                    }
                    if let weekly = preview.weeklyAmountYen {
                        previewRow(week.map { Text("budgetReview.preview.weekly \($0.daysLeftInWeek)") } ?? Text("analysis.guidance.weekly"),
                                   weekly, id: "budgetReview.preview.weekly")
                    }
                }
                Text("budgetReview.preview.note")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("budgetReview.preview.invalid")
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("budgetReview.preview.invalid")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("budgetReview.preview")
    }

    private func previewRow(_ label: Text, _ yen: Int, id: String) -> some View {
        AdaptiveStack(spacing: Spacing.xs) {
            label.font(.subheadline).foregroundStyle(Theme.secondaryText)
            Spacer(minLength: Spacing.xs)
            YenText(yen).font(.amount).foregroundStyle(Theme.text)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    // MARK: Confirm

    private var confirmBar: some View {
        VStack(spacing: 6) {
            if form.saveFailed {
                Text("budgetReview.failed")
                    .font(.caption)
                    .foregroundStyle(Theme.destructive)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("budgetReview.failed")
            }
            Button {
                if form.confirm() { dismiss() }
            } label: {
                Text(form.choice == .keep ? "budgetReview.confirm.keep" : "budgetReview.confirm.change")
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            .disabled(!form.canConfirm)
            .accessibilityIdentifier("budgetReview.confirm")
        }
        .screenInset()
        .padding(.top, 10)
        .padding(.bottom, Spacing.xs)
        .background(Theme.groundLight)
        .overlay(alignment: .top) { Divider().overlay(Theme.border) }
    }
}

/// One choice: a radio mark, its name and what it changes. Selected is said by VoiceOver, not
/// shown by color alone.
private struct ReviewChoiceRow: View {
    let title: String
    let detail: String
    let selected: Bool
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(.bodyEmphasis).foregroundStyle(Theme.text)
                    Text(verbatim: detail).font(.caption).foregroundStyle(Theme.secondaryText)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Spacing.s)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: detail))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier(id)
    }
}

// MARK: - Wording

extension InsightWording {
    /// "Suggested: raise budget", or "No suggestion yet" with too little history.
    static func recommendationTitle(_ review: BudgetReview) -> String {
        guard review.suggested.yen != nil else { return String(localized: "budgetReview.tag.none") }
        switch review.recommendation {
        case .keep: return String(localized: "budgetReview.tag.keep")
        case .raise: return String(localized: "budgetReview.tag.raise")
        case .lower: return String(localized: "budgetReview.tag.lower")
        }
    }

    /// The one-line reason for the recommendation.
    static func recommendationReason(_ review: BudgetReview) -> String {
        guard review.suggested.yen != nil else {
            return String(localized: "budgetReview.reason.limited \(BudgetReview.minimumBaselineMonths)")
        }
        switch review.recommendation {
        case .keep(.oneOffOverspend):
            return String(localized: "budgetReview.reason.oneOff \(LedgerFormat.monthName(review.month))")
        case .keep(.noChangeNeeded):
            return String(localized: "budgetReview.reason.noChange")
        case .raise(_, let category):
            return String(localized: "budgetReview.reason.raise \(category.displayName(for: LedgerFormat.language)) \(BudgetReview.monthsChecked)")
        case .lower:
            return String(localized: "budgetReview.reason.lower \(BudgetReview.monthsChecked)")
        }
    }

    /// "Based on August, September and October, without large one-offs…", or nil without a suggestion.
    static func suggestedBasis(_ review: BudgetReview) -> String? {
        guard review.suggested.yen != nil, let baseline = review.analysis.insight.comparison?.baseline else { return nil }
        return String(localized: "budgetReview.basis \(months(baseline.months)) \(LedgerFormat.yen(BudgetReview.roundingYen))")
    }

    static func choiceTitle(_ choice: BudgetReview.Choice) -> String {
        switch choice {
        case .keep: String(localized: "budgetReview.choice.keep")
        case .thisMonthOnly: String(localized: "budgetReview.choice.month")
        case .fromThisMonthOn: String(localized: "budgetReview.choice.future")
        }
    }

    static func choiceDetail(_ choice: BudgetReview.Choice, review: BudgetReview) -> String {
        let month = LedgerFormat.monthName(review.month)
        switch choice {
        case .keep:
            return review.currentBudget.yen.map { String(localized: "budgetReview.choice.keep.detail \(LedgerFormat.yen($0))") } ?? ""
        case .thisMonthOnly:
            return String(localized: "budgetReview.choice.month.detail \(month)")
        case .fromThisMonthOn:
            return String(localized: "budgetReview.choice.future.detail \(month) \(LedgerFormat.monthName(review.month.next))")
        }
    }

    static func choiceID(_ choice: BudgetReview.Choice) -> String {
        switch choice {
        case .keep: "budgetReview.choice.keep"
        case .thisMonthOnly: "budgetReview.choice.month"
        case .fromThisMonthOn: "budgetReview.choice.future"
        }
    }

    /// The same inline errors as the budget sheet (B-04).
    static func problem(_ problem: MonthlyBudget.Problem) -> String {
        switch problem {
        case .notPositive: String(localized: "budget.problem.notPositive")
        case .notWholeYen: String(localized: "budget.problem.notWholeYen")
        case .tooLarge: String(localized: "budget.problem.tooLarge")
        }
    }
}
