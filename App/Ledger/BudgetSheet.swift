import KakeiboCore
import KakeiboStore
import SwiftUI

/// "November budget": set, change or remove the current month's budget (v1.1, B-04).
/// Logic is in `BudgetForm`; this view only binds to it.
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
                VStack(alignment: .leading, spacing: 14) {
                    amountCard
                    templateCard
                    Label("budget.note", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    if form.hasBudget { removeButton }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            saveBar
        }
        .background(Theme.groundLight.ignoresSafeArea())
        .overlay {
            if confirmRemove {
                ConfirmPanel(
                    title: "budget.remove.title \(monthName)",
                    message: "budget.remove.message",
                    confirmTitle: "budget.remove.action",
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
        Group {
            if isAccessibilityTextSize {
                // Huge text: the title gets its own line under Cancel instead of drawing over it.
                VStack(alignment: .leading, spacing: 4) {
                    cancelButton
                    title.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ZStack {
                    title.padding(.horizontal, 88)
                    HStack { cancelButton; Spacer() }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
        // Opaque, so the form scrolling under it never shows through the title at large sizes.
        .background(Theme.groundLight)
    }

    private var title: some View {
        Text("budget.sheet.title \(monthName)").font(.screenTitle).foregroundStyle(Theme.text)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var cancelButton: some View {
        Button("budget.sheet.cancel") { dismiss() }
            .font(.body.weight(.medium))
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(Theme.accent)
            .accessibilityIdentifier("budget.cancel")
    }

    // MARK: Amount

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("budget.amount.label")
                .font(.caption).tracking(0.6)
                .foregroundStyle(Theme.secondaryText)
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
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
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
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $form.useForFutureMonths) {
                Text("budget.template.title").font(.body.weight(.medium)).foregroundStyle(Theme.text)
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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(form.useForFutureMonths ? Theme.accentTint : Theme.field, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("budget.template.explanation")
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Remove and save

    private var removeButton: some View {
        Button(role: .destructive) { confirmRemove = true } label: {
            Text("budget.remove").frame(maxWidth: .infinity, minHeight: 44)
        }
        .foregroundStyle(Theme.destructive)
        .accessibilityIdentifier("budget.remove")
    }

    private var saveBar: some View {
        VStack(spacing: 6) {
            if let failure = form.failure {
                Text(failure == .save ? "budget.saveFailed" : "budget.removeFailed")
                    .font(.caption)
                    .foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("budget.failed")
            }
            Button {
                if form.save() { dismiss() }
            } label: {
                Text("budget.save").frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle())
            .disabled(!form.canSave)
            .accessibilityIdentifier("budget.save")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.groundLight)
        .overlay(alignment: .top) { Divider().overlay(Theme.border) }
    }
}
