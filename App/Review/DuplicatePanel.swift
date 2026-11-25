import KakeiboCore
import KakeiboStore
import SwiftUI

/// "Already saved?": shown when Save finds a saved expense that looks like this one.
/// Warns but never blocks: the same purchase twice in a day is real.
///
/// B-16: a new scan or manual entry can also replace the saved entry (a rescan of a poor
/// first scan). With a strong match (same receipt number) Replace is the main action; with a
/// likely match, viewing the saved entry is.
struct DuplicatePanel: View {
    let match: ExpenseRepository.PossibleDuplicate
    let onView: () -> Void
    /// Nil when this form cannot replace (editing a saved expense).
    let onReplace: (() -> Void)?
    let onSaveAsNew: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ActionPanel(
            systemImage: "doc.on.doc",
            tone: .warning,
            title: "duplicate.title",
            message: message,
            onDismiss: onCancel
        ) {
            EntrySummary.saved(match.expense)
                .accessibilityIdentifier("duplicate.entry")
        } actions: {
            if let onReplace, match.strength == .strong {
                replaceButton(onReplace).buttonStyle(PrimaryButtonStyle(fullWidth: true))
                viewButton.buttonStyle(SecondaryButtonStyle(fullWidth: true))
            } else {
                viewButton.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                if let onReplace {
                    replaceButton(onReplace).buttonStyle(SecondaryButtonStyle(fullWidth: true))
                }
            }
            Button(action: onSaveAsNew) { Text("duplicate.saveAsNew") }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("duplicate.saveAsNew")
            Button(action: onCancel) { Text("duplicate.cancel") }
                .buttonStyle(TextButtonStyle())
                .accessibilityIdentifier("duplicate.cancel")
        }
        .accessibilityIdentifier("duplicate")
    }

    private var message: LocalizedStringKey {
        switch (match.strength, onReplace != nil) {
        case (.strong, true): "duplicate.message.strong.replace"
        case (.strong, false): "duplicate.message.strong"
        case (.likely, true): "duplicate.message.likely.replace"
        case (.likely, false): "duplicate.message.likely"
        }
    }

    private var viewButton: some View {
        Button(action: onView) { Text("duplicate.view") }
            .accessibilityIdentifier("duplicate.view")
    }

    private func replaceButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text("duplicate.replace") }
            .accessibilityIdentifier("duplicate.replace")
    }
}

extension EntrySummary {
    /// A saved expense: "Thu, Nov 5 · 木  14:32" and "Groceries · IC card".
    static func saved(_ expense: Expense) -> EntrySummary {
        EntrySummary(
            category: expense.category,
            storeName: expense.storeName,
            amount: expense.totalYen,
            lines: [
                [LedgerFormat.dayTitle(expense.dayKey), expense.time].compactMap { $0 }.joined(separator: "  "),
                "\(expense.category.displayName(for: LedgerFormat.language)) · \(expense.payment.shortLabel)",
            ]
        )
    }

    /// The form being saved, for the save-failure panel.
    static func draft(_ draft: ReceiptDraft) -> EntrySummary {
        let category = draft.category ?? .other
        var lines: [String] = []
        if let dayKey = draft.dayKey {
            lines.append([LedgerFormat.dayTitle(dayKey), draft.time].compactMap { $0 }.joined(separator: "  "))
        }
        var detail = [category.displayName(for: LedgerFormat.language)]
        if let payment = draft.payment { detail.append(payment.shortLabel) }
        lines.append(detail.joined(separator: " · "))
        return EntrySummary(category: category, storeName: draft.storeName ?? "", amount: draft.totalYen, lines: lines)
    }
}
