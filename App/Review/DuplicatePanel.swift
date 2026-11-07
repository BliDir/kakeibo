import KakeiboCore
import KakeiboStore
import SwiftUI

/// "Already saved?": shown when Save finds a saved expense that looks like this one.
/// Warns but never blocks: the same purchase twice in a day is real.
struct DuplicatePanel: View {
    let match: ExpenseRepository.PossibleDuplicate
    let onView: () -> Void
    let onSaveAnyway: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ActionPanel(
            systemImage: "doc.on.doc",
            tone: .warning,
            title: "duplicate.title",
            message: match.strength == .strong ? "duplicate.message.strong" : "duplicate.message.likely",
            onDismiss: onCancel
        ) {
            EntrySummary.saved(match.expense)
                .accessibilityIdentifier("duplicate.entry")
        } actions: {
            Button(action: onView) { Text("duplicate.view") }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("duplicate.view")
            Button(action: onSaveAnyway) { Text("duplicate.saveAnyway") }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("duplicate.saveAnyway")
            Button(action: onCancel) { Text("duplicate.cancel") }
                .buttonStyle(TextButtonStyle())
                .accessibilityIdentifier("duplicate.cancel")
        }
        .accessibilityIdentifier("duplicate")
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
