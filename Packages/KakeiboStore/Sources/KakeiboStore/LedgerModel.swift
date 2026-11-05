import Foundation
import KakeiboCore
import Observation
import SwiftData

extension Expense: LedgerItem {}

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

    public let repository: ExpenseRepository
    /// Budgets; nil where budgets are not wired in (older tests and previews).
    public let budgets: BudgetRepository?
    private let today: () -> Date
    private var observer: (any NSObjectProtocol)?

    /// - Parameter today: the current date; the ledger opens on its month and never goes past it.
    public init(repository: ExpenseRepository, budgets: BudgetRepository? = nil, today: @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.budgets = budgets
        self.today = today
        month = LedgerMonth(containing: today())
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

    public func reload() {
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
        }
        days = DayGroup.group(expenses)
    }
}
