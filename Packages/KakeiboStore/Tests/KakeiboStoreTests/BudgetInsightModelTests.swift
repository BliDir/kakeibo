import Foundation
import KakeiboCore
import SwiftData
import Testing
@testable import KakeiboStore

/// The ledger's over-budget insight (v1.2, BI-04): `LedgerModel.overspend` and the history it reads.
@MainActor
@Suite struct BudgetInsightModelTests {
    let container: ModelContainer
    let repo: ExpenseRepository
    let budgets: BudgetRepository
    static let today = Date(timeIntervalSince1970: 1_795_143_600) // 2026-11-20 12:00 Tokyo

    init() throws {
        container = try KakeiboStore.makeContainer(inMemory: true)
        repo = ExpenseRepository(container: container)
        budgets = BudgetRepository(context: repo.context)
    }

    private func model() -> LedgerModel {
        LedgerModel(repository: repo, budgets: budgets, today: { Self.today })
    }

    @discardableResult
    private func add(_ day: String, _ total: Int, _ category: ExpenseCategory = .groceries,
                     store: String = "西友") throws -> Expense {
        try repo.create(from: ReceiptDraft(storeName: store, dayKey: day, totalYen: total, category: category),
                        source: .manual, now: Self.today)
    }

    /// August to October: ¥30,000 of groceries and ¥5,000 of dining out each month.
    private func addUsualMonths() throws {
        for month in ["2026-08", "2026-09", "2026-10"] {
            try add("\(month)-10", 30_000)
            try add("\(month)-12", 5_000, .dining, store: "さくら食堂")
        }
    }

    /// A past month's budget (the repository only sets the current month).
    private func setPastBudget(_ yen: Int, _ monthKey: String) throws {
        repo.context.insert(BudgetMonth(monthKey: monthKey, budgetYen: yen, createdAt: Self.today, updatedAt: Self.today))
        try repo.context.save()
    }

    @Test func noBudgetHasNoInsight() throws {
        try addUsualMonths()
        try add("2026-11-02", 90_000)
        #expect(model().overspend == nil)
    }

    @Test func underPaceHasNoInsight() throws {
        try addUsualMonths()
        try budgets.setBudget(100_000, for: LedgerMonth(year: 2026, month: 11), now: Self.today)
        try add("2026-11-02", 20_000)
        #expect(model().overspend == nil)
    }

    @Test func overBudgetUsesTheEarlierMonthsAsBaseline() throws {
        try addUsualMonths()
        try budgets.setBudget(40_000, for: LedgerMonth(year: 2026, month: 11), now: Self.today)
        try add("2026-11-03", 20_000)
        try add("2026-11-05", 22_000, .dining, store: "さくら食堂")
        let analysis = try #require(model().overspend)

        #expect(analysis.insight.state == .overBudget)
        #expect(!analysis.isLimitedHistory)
        #expect(analysis.insight.comparison?.baseline.months.map(\.key) == ["2026-10", "2026-09", "2026-08"])
        #expect(analysis.basisYen == 2_000)
        #expect(analysis.drivers.first?.target == .category(.dining))
        #expect(analysis.dailyAmountYen == 0)
    }

    @Test func savingAnExpenseUpdatesTheInsight() throws {
        try addUsualMonths()
        try budgets.setBudget(100_000, for: LedgerMonth(year: 2026, month: 11), now: Self.today)
        let ledger = model()
        try add("2026-11-03", 50_000)
        #expect(ledger.overspend == nil)
        try add("2026-11-04", 35_000)        // 85%: on pace to overspend
        #expect(ledger.overspend?.insight.state == .onPaceToOverspend)
        try add("2026-11-05", 20_000)        // 105%
        #expect(ledger.overspend?.insight.state == .overBudget)
    }

    @Test func closedMonthOverBudgetIsReadOnly() throws {
        try addUsualMonths()
        try setPastBudget(30_000, "2026-10")
        let ledger = model()
        ledger.showPrevious()
        let analysis = try #require(ledger.overspend)
        #expect(analysis.insight.state == .closedMonthOverBudget)
        #expect(analysis.dailyAmountYen == nil)
        #expect(analysis.weeklyAmountYen == nil)
        #expect(analysis.insight.comparison?.baseline.months.map(\.key) == ["2026-09", "2026-08"])
    }

    @Test func noEarlierMonthIsLimitedHistory() throws {
        try budgets.setBudget(10_000, for: LedgerMonth(year: 2026, month: 11), now: Self.today)
        try add("2026-11-03", 8_000)
        try add("2026-11-04", 4_000, .dining, store: "さくら食堂")
        let analysis = try #require(model().overspend)
        #expect(analysis.isLimitedHistory)
        #expect(analysis.drivers.map(\.kind) == [.shareOfBudget, .shareOfBudget])
    }

    /// The baseline skips empty months, within the 12 months read.
    @Test func historySkipsEmptyMonths() throws {
        try add("2025-11-10", 10_000)   // 12 months back: read
        try add("2025-10-10", 10_000)   // 13 months back: not read
        try add("2026-06-10", 10_000)
        try budgets.setBudget(5_000, for: LedgerMonth(year: 2026, month: 11), now: Self.today)
        try add("2026-11-03", 8_000)
        let analysis = try #require(model().overspend)
        #expect(analysis.insight.comparison?.baseline.months.map(\.key) == ["2026-06", "2025-11"])
    }

    @Test func expensesForATargetFilterTheShownMonth() throws {
        try add("2026-11-03", 1_000, .dining, store: "さくら食堂")
        try add("2026-11-04", 2_000, .dining, store: "スターバックス")
        try add("2026-11-05", 3_000, .groceries, store: "さくら食堂")
        try add("2026-10-05", 4_000, .dining, store: "さくら食堂")
        let ledger = model()
        #expect(ledger.expenses(for: .category(.dining)).map(\.totalYen) == [2_000, 1_000])
        #expect(ledger.expenses(for: .store("さくら食堂")).map(\.totalYen) == [3_000, 1_000])
    }

    @Test func rangeFetchIncludesTheFirstMonthAndExcludesTheEnd() throws {
        try add("2026-07-31", 1)
        try add("2026-08-01", 2)
        try add("2026-10-31", 3)
        try add("2026-11-01", 4)
        let found = try repo.expenses(from: LedgerMonth(year: 2026, month: 8), before: LedgerMonth(year: 2026, month: 11))
        #expect(found.map(\.totalYen) == [3, 2])
        #expect(try repo.expenses(from: LedgerMonth(year: 2026, month: 11), before: LedgerMonth(year: 2026, month: 11)).isEmpty)
    }
}
