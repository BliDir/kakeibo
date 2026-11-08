import Foundation
import KakeiboCore
import Observation
import SwiftData

extension Expense: LedgerItem {}
extension Expense: InsightItem {}

/// The ledger home screen's state: one month's expenses, grouped by day, with totals.
///
/// Reads through `ExpenseRepository` and reloads whenever the repository's context saves,
/// so the list updates after a save or delete anywhere in the app.
@MainActor
@Observable
public final class LedgerModel {
    public private(set) var month: LedgerMonth
    public private(set) var expenses: [Expense] = []
    public private(set) var summary: MonthSummary = .empty
    /// The month before `month`, for "September ¥178,180 · +¥8,240".
    public private(set) var previousSummary: MonthSummary = .empty
    public private(set) var days: [DayGroup<Expense>] = []
    /// Set when the last load failed; the screen keeps showing what it had.
    public private(set) var loadFailed = false
    /// The shown month's budget against its spend (v1.1). `.unset` status when there is none.
    public private(set) var budgetSummary: BudgetSummary?
    /// Why the shown month is over (or on pace to go over) its budget (v1.2, BI-02/BI-04).
    /// Nil when it has no insight: no budget, under pace, or figures that could not be read.
    public private(set) var overspend: OverspendAnalysis?

    public let repository: ExpenseRepository
    /// Budgets; nil where budgets are not wired in (older tests and previews).
    public let budgets: BudgetRepository?
    private let today: () -> Date
    private var observer: (any NSObjectProtocol)?
    /// The current month when the model last loaded, to notice a Tokyo month rollover.
    private var loadedCurrentMonth: LedgerMonth

    /// - Parameter today: the current date; the ledger opens on its month and never goes past it.
    public init(repository: ExpenseRepository, budgets: BudgetRepository? = nil, today: @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.budgets = budgets
        self.today = today
        let current = LedgerMonth(containing: today())
        month = current
        loadedCurrentMonth = current
        reload()
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: repository.context, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public var currentMonth: LedgerMonth { LedgerMonth(containing: today()) }

    /// False on the current month: there is nothing to show in the future.
    public var canShowNext: Bool { month < currentMonth }

    public var isEmpty: Bool { expenses.isEmpty }

    /// The budget can be set, changed or removed only for the current month.
    public var canEditBudget: Bool { budgets != nil && month == currentMonth }

    /// The form for the budget sheet, or nil when the month is read-only or it cannot be read.
    public func makeBudgetForm() -> BudgetForm? {
        guard canEditBudget, let budgets else { return nil }
        return try? BudgetForm(repository: budgets, month: month, now: today())
    }

    /// The budget review for the shown month (BI-05), or nil when it has no budget or its figures
    /// cannot be read. Uses the same history as `overspend`, plus the stored budgets of those
    /// months. A past month's review is read only.
    public func makeBudgetReview() -> BudgetReviewForm? {
        guard let budgets, !loadFailed, let budget = try? budgets.budget(for: month, now: today()),
              case .yen = budget else { return nil }
        let first = historyStart
        guard let history = try? repository.expenses(from: first, before: month),
              let pastBudgets = try? budgets.budgets(from: first, before: month) else { return nil }
        let review = BudgetReview(month: month, budget: budget, items: expenses, history: history,
                                  pastBudgets: pastBudgets, now: today())
        return BudgetReviewForm(review: review, repository: budgets, now: today)
    }

    /// The first month read for the insight history.
    private var historyStart: LedgerMonth {
        var first = month
        for _ in 0..<Self.insightHistoryMonths { first = first.previous }
        return first
    }

    /// How many months before the shown one are read for the insight baseline. The baseline
    /// uses the last 3 of them that have an expense, so a few empty months are skipped.
    public static let insightHistoryMonths = 12

    /// The shown month's expenses in a driver's category or store, newest first (the filtered
    /// ledger opened from the analysis).
    public func expenses(for target: InsightTarget) -> [Expense] {
        expenses.filter { target.matches($0) }
    }

    /// This month against the one before.
    public var comparison: MonthComparison { MonthComparison(current: summary, previous: previousSummary) }

    public func showPrevious() { show(month.previous) }

    public func showNext() {
        guard canShowNext else { return }
        show(month.next)
    }

    /// Shows `month`, clamped to the current month.
    public func show(_ month: LedgerMonth) {
        self.month = min(month, currentMonth)
        reload()
    }

    /// Call when the app comes to the foreground and at Tokyo midnight (see
    /// `Calendar.startOfNextDay(after:)`): "today" may have moved, which changes the weekly
    /// allowance and maybe the month. If the ledger was showing the month that was current, it
    /// moves on to the new current month; a past month being browsed stays where it is.
    public func refreshForCurrentDate() {
        let current = currentMonth
        if current != loadedCurrentMonth, month == loadedCurrentMonth {
            month = current
        }
        reload()
    }

    public func reload() {
        loadedCurrentMonth = currentMonth
        do {
            expenses = try repository.expenses(inMonth: month.key)
            previousSummary = MonthSummary(try repository.expenses(inMonth: month.previous.key))
            loadFailed = false
        } catch {
            loadFailed = true
        }
        summary = MonthSummary(expenses)
        if let budgets {
            // A failed budget read shows the month without budget figures rather than wrong ones.
            let budget = (try? budgets.budget(for: month, now: today())) ?? .unset
            budgetSummary = BudgetSummary(month: month, budget: budget, items: expenses, now: today())
            overspend = loadFailed ? nil : analysis(budget: budget)
        }
        days = DayGroup.group(expenses)
    }

    /// BI-02's analysis of the shown month, or nil when it has no insight card.
    private func analysis(budget: MonthlyBudget) -> OverspendAnalysis? {
        // Only a set budget can be over; skip reading the history otherwise.
        guard case .yen = budget else { return nil }
        guard let history = try? repository.expenses(from: historyStart, before: month) else { return nil }
        let analysis = OverspendAnalysis(month: month, budget: budget, items: expenses, history: history, now: today())
        return analysis.insight.state == .none ? nil : analysis
    }
}
