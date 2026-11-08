import KakeiboCore
import KakeiboStore
import SwiftUI

/// The ledger filtered to one driver's category or store for the analysed month (v1.2, BI-04),
/// opened from a driver row on the analysis. Back returns to the analysis; a row opens the
/// expense's details. Reads the same `LedgerModel`, so it updates after a save or delete.
struct FilteredLedgerView: View {
    let model: LedgerModel
    let target: InsightTarget
    let photoStore: PhotoStore?
    let onSelect: (Expense) -> Void

    @Environment(\.dismiss) private var dismiss

    private var expenses: [Expense] { model.expenses(for: target) }
    private var name: String { InsightWording.name(target) }

    var body: some View {
        let expenses = expenses
        let summary = MonthSummary(expenses)
        VStack(spacing: 0) {
            TitleBar(title: "filtered.title") {
                Button { dismiss() } label: {
                    Label("filtered.back", systemImage: "chevron.backward")
                }
                .buttonStyle(TextButtonStyle())
                .accessibilityIdentifier("filtered.back")
            } trailing: {
                EmptyView()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(verbatim: LedgerFormat.monthTitle(model.month)).eyebrow(uppercase: false)
                        Text(verbatim: name)
                            .font(.pageTitle)
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Tag("filtered.tag \(name)")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        YenText(summary.totalYen)
                            .font(.amountHero)
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .accessibilityIdentifier("filtered.total")
                        Text("ledger.receipts \(summary.count)")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityIdentifier("filtered.count")
                    }
                    if expenses.isEmpty {
                        Text("filtered.empty")
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .card()
                    } else {
                        ForEach(DayGroup.group(expenses), id: \.dayKey) { day in
                            DaySection(day: day, photoStore: photoStore, onSelect: onSelect)
                        }
                    }
                }
                .screenInset()
                .padding(.vertical, Spacing.s)
            }
        }
        .background(Theme.groundLight.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filtered.screen")
    }
}
