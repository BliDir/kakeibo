import KakeiboCore
import KakeiboStore
import SwiftUI

/// "November budget": set, change or remove the current month's budget (v1.1, B-04; visual
/// refresh, UI-06). Logic is in `BudgetForm`; this view only binds to it.
struct BudgetSheet: View {
    @Bindable var form: BudgetForm
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false
    @FocusState private var amountFocused: Bool
    @Environment(\.isAccessibilityTextSize) private var isAccessibilityTextSize

    private var monthName: String { LedgerFormat.monthName(form.month) }
    private var nextMonthName: String { LedgerFormat.monthName(form.month.next) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    intro
                    amountCard
                    templateCard
                    Label("budget.note", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    // At the accessibility sizes the save bar would cover most of the screen
                    // above the keyboard, so Remove moves into the form there.
                    if form.hasBudget && isAccessibilityTextSize { removeButton }
                }
                .screenInset()
                .padding(.vertical, Spacing.s)
            }
            .scrollDismissesKeyboard(.interactively)
            saveBar
        }
        .background(Theme.groundLight.ignoresSafeArea())
        .overlay {
            if confirmRemove {
                ConfirmPanel(
                    systemImage: "chart.pie",
                    title: "budget.remove.title \(monthName)",
                    message: "budget.remove.message",
                    confirmTitle: "budget.remove.action",
                    keepTitle: "budget.remove.keep",
                    onConfirm: {
                        confirmRemove = false
                        if form.remove() { dismiss() }
                    },
                    onCancel: { confirmRemove = false }
                )
            }
        }
        .onAppear { if !form.hasBudget { amountFocused = true } }
        // VoiceOver users are typing in the field and would not hear the error appear under it.
        .onChange(of: problemAnnouncement) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("budget.sheet")
    }

    // MARK: Header

    private var header: some View {
        TitleBar(title: "budget.sheet.title \(monthName)") {
            Button("budget.sheet.cancel") { dismiss() }
                .buttonStyle(TextButtonStyle())
                .accessibilityIdentifier("budget.cancel")
        } trailing: {
            EmptyView()
        }
        // Opaque, so the form scrolling under it never shows through the title at large sizes.
        .background(Theme.groundLight)
    }

    /// "NOVEMBER 2026" and "Give your spending a little direction."
    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: LedgerFormat.monthTitle(form.month)).eyebrow()
            Text("budget.sheet.headline")
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    // MARK: Amount

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("budget.amount.label").eyebrow(uppercase: false)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                let symbol = Yen.fieldSymbol(for: LedgerFormat.language)
                if symbol.isPrefix { Text(verbatim: symbol.symbol).font(.amountHero).foregroundStyle(Theme.secondaryText) }
                TextField(text: $form.amountText, prompt: Text(verbatim: "0")) { Text("budget.amount.label") }
                    .font(.amountHero)
                    .keyboardType(.numberPad)
                    .focused($amountFocused)
                    .accessibilityIdentifier("budget.amount")
                if !symbol.isPrefix { Text(verbatim: symbol.symbol).font(.title.weight(.semibold)).foregroundStyle(Theme.secondaryText) }
            }
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                Rectangle().fill(form.problem.map(isTypedProblem) == true ? Theme.destructive : Theme.accent).frame(height: 2)
            }
            if let message = problemMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.destructive)
                    .accessibilityIdentifier("budget.problem")
            }
            Text("budget.amount.help \(monthName)")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    /// Only complain about what was typed, not about an empty field.
    private func isTypedProblem(_ problem: MonthlyBudget) -> Bool {
        if case .invalid = problem { true } else { false }
    }

    private var problemMessage: LocalizedStringKey? {
        guard case .invalid(let problem) = form.parsed else { return nil }
        switch problem {
        case .notPositive: return "budget.problem.notPositive"
        case .notWholeYen: return "budget.problem.notWholeYen"
        case .tooLarge: return "budget.problem.tooLarge"
        }
    }

    private var problemAnnouncement: String? {
        guard case .invalid(let problem) = form.parsed else { return nil }
        switch problem {
        case .notPositive: return String(localized: "budget.problem.notPositive")
        case .notWholeYen: return String(localized: "budget.problem.notWholeYen")
        case .tooLarge: return String(localized: "budget.problem.tooLarge")
        }
    }

    // MARK: Template

    private var templateCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Toggle(isOn: $form.useForFutureMonths) {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 36, height: 36)
                        .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)
                    Text("budget.template.title")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("budget.template")
            Group {
                if form.useForFutureMonths {
                    if let yen = form.parsed.yen {
                        Text("budget.template.on \(nextMonthName) \(LedgerFormat.yen(yen))")
                    } else {
                        Text("budget.template.on.noAmount \(nextMonthName)")
                    }
                } else {
                    Text("budget.template.off \(monthName)")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(form.useForFutureMonths ? Theme.accentTint : Theme.field,
                        in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            .accessibilityIdentifier("budget.template.explanation")
        }
        .card()
    }

    // MARK: Save and remove

    /// Remove this month's budget (vermilion text), after a confirmation.
    private var removeButton: some View {
        Button { confirmRemove = true } label: {
            Text("budget.remove")
        }
        .buttonStyle(DestructiveButtonStyle())
        .accessibilityIdentifier("budget.remove")
    }

    /// Save (solid green), then Remove for a month that has a budget (in the form instead at
    /// the accessibility sizes).
    private var saveBar: some View {
        VStack(spacing: 6) {
            if let failure = form.failure {
                Text(failure == .save ? "budget.saveFailed" : "budget.removeFailed")
                    .font(.caption)
                    .foregroundStyle(Theme.destructive)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("budget.failed")
            }
            Button {
                if form.save() { dismiss() }
            } label: {
                Text("budget.save")
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            .disabled(!form.canSave)
            .accessibilityIdentifier("budget.save")
            if form.hasBudget && !isAccessibilityTextSize { removeButton }
        }
        .screenInset()
        .padding(.top, 10)
        .padding(.bottom, Spacing.xs)
        .background(Theme.groundLight)
        .overlay(alignment: .top) { Divider().overlay(Theme.border) }
    }
}
