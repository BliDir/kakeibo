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
        ZStack(alignment: .bottom) {
            Theme.scrim
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)
            VStack(spacing: 14) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                    .accessibilityHidden(true)
                Text("duplicate.title").font(.headline).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                Text(match.strength == .strong ? "duplicate.message.strong" : "duplicate.message.likely")
                    .font(.subheadline).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                savedEntry
                Button(action: onView) {
                    Text("duplicate.view").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Theme.onAccent)
                .accessibilityIdentifier("duplicate.view")
                Button(action: onSaveAnyway) {
                    Text("duplicate.saveAnyway").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
                .foregroundStyle(Theme.accent)
                .accessibilityIdentifier("duplicate.saveAnyway")
                Button(action: onCancel) {
                    Text("duplicate.cancel").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .foregroundStyle(Theme.accent)
                .accessibilityIdentifier("duplicate.cancel")
            }
            .padding(20)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
            .padding(16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("duplicate")
        }
        .transition(.opacity)
    }

    /// The saved entry: store, date, time and amount.
    private var savedEntry: some View {
        let expense = match.expense
        return HStack(spacing: 12) {
            CategoryBadge(category: expense.category, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: expense.storeName.isEmpty ? "—" : expense.storeName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Text(verbatim: [LedgerFormat.dayTitle(expense.dayKey), expense.time].compactMap { $0 }.joined(separator: "  "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(verbatim: LedgerFormat.yen(expense.totalYen))
                .font(.amount)
                .foregroundStyle(Theme.text)
        }
        .padding(12)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("duplicate.entry")
    }
}
