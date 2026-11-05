import Foundation
import KakeiboCore
import SwiftData
import Testing
@testable import KakeiboStore

private struct SaveFailed: Error {}

private func tokyo(_ dayKey: String) -> Date {
    let p = dayKey.split(separator: "-").map { Int($0)! }
    return Calendar.kakeibo.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!
}

@MainActor
@Suite struct BudgetFormTests {
    let container: ModelContainer
    let budgets: BudgetRepository
    let expenses: ExpenseRepository
    static let nov = LedgerMonth(year: 2026, month: 11)
    static let now = tokyo("2026-11-05")

    init() throws {
        container = try KakeiboStore.makeContainer(inMemory: true)
        budgets = BudgetRepository(container: container)
        expenses = ExpenseRepository(container: container)
    }

    private func form() throws -> BudgetForm { try BudgetForm(repository: budgets, month: Self.nov, now: Self.now) }

    // MARK: Setup and validation

    @Test func newFormIsEmptyWithTemplateOff() throws {
        let f = try form()
        #expect(f.amountText.isEmpty)
        #expect(!f.useForFutureMonths, "the future-month toggle defaults off")
        #expect(!f.hasBudget)
        #expect(!f.canSave)
        #expect(f.problem == .unset)
        #expect(!f.hasUnsavedChanges)
    }

    @Test(arguments: [
        ("200000", 200_000), ("200,000", 200_000), ("２００，０００", 200_000), ("¥50,000", 50_000), ("3000円", 3_000),
    ])
    func acceptsLocalizedInput(text: String, yen: Int) throws {
        let f = try form()
        f.amountText = text
        #expect(f.canSave)
        #expect(f.parsed == .yen(yen))
    }

    @Test(arguments: [
        ("0", MonthlyBudget.Problem.notPositive), ("-100", .notPositive), ("1.5", .notWholeYen),
        ("abc", .notWholeYen), ("1000000000", .tooLarge), ("99999999999999999999999", .tooLarge),
    ])
    func refusesBadInput(text: String, problem: MonthlyBudget.Problem) throws {
        let f = try form()
        f.amountText = text
        #expect(!f.canSave)
        #expect(f.problem == .invalid(problem))
        #expect(!f.save(now: Self.now))
        #expect(try budgets.row(for: Self.nov) == nil, "nothing stored")
    }

    // MARK: Set, edit, remove, re-add

    @Test func setEditRemoveAndReAdd() throws {
        let set = try form()
        set.amountText = "200,000"
        #expect(set.hasUnsavedChanges)
        #expect(set.save(now: Self.now))
        #expect(try budgets.budget(for: Self.nov, now: Self.now) == .yen(200_000))

        let edit = try form()
        #expect(edit.hasBudget)
        #expect(edit.amountText == "200000")
        edit.amountText = "180000"
        #expect(edit.save(now: Self.now))
        #expect(try budgets.budget(for: Self.nov, now: Self.now) == .yen(180_000))

        try budgets.markHandled([.eighty], for: Self.nov, now: Self.now)
        #expect(try form().remove(now: Self.now))
        #expect(try budgets.budget(for: Self.nov, now: Self.now) == .unset)
        #expect(try !form().hasBudget)

        let reAdd = try form()
        reAdd.amountText = "150000"
        #expect(reAdd.save(now: Self.now))
        #expect(try budgets.budget(for: Self.nov, now: Self.now) == .yen(150_000))
        #expect(try budgets.handledThresholds(for: Self.nov) == [.eighty], "alert history kept")
    }

    @Test func removingKeepsReceipts() throws {
        try expenses.create(from: ReceiptDraft(dayKey: "2026-11-03", totalYen: 1_310), source: .manual)
        let f = try form()
        f.amountText = "50000"
        f.save(now: Self.now)
        try form().remove(now: Self.now)
        #expect(try expenses.expenses(inMonth: "2026-11").count == 1)
    }

    // MARK: Template on and off

    @Test func templateOnAndOff() throws {
        let on = try form()
        on.amountText = "200000"
        on.useForFutureMonths = true
        #expect(on.save(now: Self.now))
        #expect(try budgets.template()?.amountYen == 200_000)
        #expect(try budgets.template()?.startMonthKey == "2026-12")
        #expect(try form().useForFutureMonths, "reopening shows it on")

        let off = try form()
        off.useForFutureMonths = false
        #expect(off.hasUnsavedChanges)
        #expect(off.save(now: Self.now))
        #expect(try budgets.template() == nil)
        #expect(try budgets.budget(for: Self.nov, now: Self.now) == .yen(200_000), "this month keeps its budget")
        #expect(try !form().useForFutureMonths)
    }

    @Test func templateFollowsAnEditedAmount() throws {
        let f = try form()
        f.amountText = "200000"
        f.useForFutureMonths = true
        f.save(now: Self.now)
        let edit = try form()
        edit.amountText = "220000"
        edit.save(now: Self.now)
        #expect(try budgets.template()?.amountYen == 220_000)
    }

    // MARK: Failures

    @Test func failedSaveStoresNothingAndReports() throws {
        budgets.beforeSave = { throw SaveFailed() }
        let f = try form()
        f.amountText = "200000"
        f.useForFutureMonths = true
        #expect(!f.save(now: Self.now))
        #expect(f.failure == .save)
        budgets.beforeSave = nil
        #expect(try budgets.row(for: Self.nov) == nil, "neither the budget...")
        #expect(try budgets.template() == nil, "...nor the template was stored")

        // Recoverable: the same form saves on the next try and clears the error.
        #expect(f.save(now: Self.now))
        #expect(f.failure == nil)
        #expect(try budgets.budget(for: Self.nov, now: Self.now) == .yen(200_000))
    }

    @Test func failedRemoveKeepsTheBudget() throws {
        let f = try form()
        f.amountText = "90000"
        f.save(now: Self.now)
        budgets.beforeSave = { throw SaveFailed() }
        let remove = try form()
        #expect(!remove.remove(now: Self.now))
        #expect(remove.failure == .remove)
        budgets.beforeSave = nil
        #expect(try budgets.budget(for: Self.nov, now: Self.now) == .yen(90_000))
    }

    @Test func pastMonthsCannotBeSaved() throws {
        let f = try form()
        f.amountText = "50000"
        #expect(!f.save(now: tokyo("2026-12-02")), "November is history in December")
        #expect(f.failure == .save)
    }

    // MARK: Atomic save in the repository

    @Test func saveBudgetIsAtomic() throws {
        budgets.beforeSave = { throw SaveFailed() }
        #expect(throws: SaveFailed.self) {
            try budgets.saveBudget(70_000, for: Self.nov, useForFutureMonths: true, now: Self.now)
        }
        budgets.beforeSave = nil
        #expect(try budgets.row(for: Self.nov) == nil && budgets.template() == nil)
        #expect(throws: BudgetRepository.Error.readOnlyMonth("2026-10")) {
            try budgets.saveBudget(70_000, for: LedgerMonth(year: 2026, month: 10), useForFutureMonths: false, now: Self.now)
        }
    }
}

@MainActor
@Suite struct LedgerBudgetTests {
    @Test func ledgerShowsTheMonthsBudgetAndWhetherItCanBeEdited() async throws {
        let container = try KakeiboStore.makeContainer(inMemory: true)
        let expenses = ExpenseRepository(container: container)
        let budgets = BudgetRepository(container: container)
        let now = tokyo("2026-11-05")
        try expenses.create(from: ReceiptDraft(dayKey: "2026-11-03", totalYen: 40_000), source: .manual)
        let model = LedgerModel(repository: expenses, budgets: budgets, today: { now })

        #expect(model.budgetSummary?.status == .unset)
        #expect(model.canEditBudget)
        #expect(model.makeBudgetForm() != nil)

        // Saving through the form updates the ledger (it reloads on save).
        let form = try #require(model.makeBudgetForm())
        form.amountText = "100000"
        form.save(now: now)
        await Task.yield()
        #expect(model.budgetSummary?.budgetYen == 100_000)
        #expect(model.budgetSummary?.remainingYen == 60_000)

        // A past month is read-only: no form.
        model.showPrevious()
        #expect(!model.canEditBudget)
        #expect(model.makeBudgetForm() == nil)
        #expect(model.budgetSummary?.status == .unset)
    }

    @Test func ledgerWithoutBudgetsStillWorks() throws {
        let expenses = ExpenseRepository(container: try KakeiboStore.makeContainer(inMemory: true))
        let model = LedgerModel(repository: expenses, today: { tokyo("2026-11-05") })
        #expect(model.budgetSummary == nil)
        #expect(!model.canEditBudget)
    }

    @Test func progressUsesBudgetAndRecordedSpend() throws {
        let container = try KakeiboStore.makeContainer(inMemory: true)
        let expenses = ExpenseRepository(container: container)
        let budgets = BudgetRepository(container: container)
        let now = tokyo("2026-11-05")   // Thursday: D = 26, W = 4
        try budgets.setBudget(200_000, for: LedgerMonth(year: 2026, month: 11), now: now)
        try expenses.create(from: ReceiptDraft(dayKey: "2026-11-02", totalYen: 30_000), source: .scan)
        try expenses.create(from: ReceiptDraft(dayKey: "2026-11-05", totalYen: 11_860), source: .manual)
        let model = LedgerModel(repository: expenses, budgets: budgets, today: { now })
        let s = try #require(model.budgetSummary)
        #expect(s.spentYen == 41_860)
        #expect(s.remainingYen == 158_140)
        #expect(s.percentSpent == 20)
        // This week's ¥11,860 is in S once; the allowance is not reduced by it again.
        #expect(s.weeklyAllowance?.yen == 158_140 / 26 * 4 + (158_140 % 26) * 4 / 26)
        #expect(s.weeklyAllowance?.yen == 24_329)
    }

    @Test func movingAnExpenseToAnotherMonthUpdatesSpend() async throws {
        let container = try KakeiboStore.makeContainer(inMemory: true)
        let expenses = ExpenseRepository(container: container)
        let budgets = BudgetRepository(container: container)
        let now = tokyo("2026-11-05")
        try budgets.setBudget(50_000, for: LedgerMonth(year: 2026, month: 11), now: now)
        let expense = try expenses.create(from: ReceiptDraft(dayKey: "2026-11-03", totalYen: 45_000), source: .manual)
        let model = LedgerModel(repository: expenses, budgets: budgets, today: { now })
        #expect(model.budgetSummary?.percentSpent == 90)

        // Edited to 31 October: November's spend drops, October's rises.
        try expenses.update(expense, from: ReceiptDraft(dayKey: "2026-10-31", totalYen: 45_000))
        await Task.yield()
        #expect(model.budgetSummary?.spentYen == 0)
        #expect(model.budgetSummary?.weeklyAllowance?.yen == 50_000 / 26 * 4 + (50_000 % 26) * 4 / 26)
        model.showPrevious()
        #expect(model.summary.totalYen == 45_000)
    }

    @Test func midnightAndMonthRolloverRefresh() throws {
        let container = try KakeiboStore.makeContainer(inMemory: true)
        let expenses = ExpenseRepository(container: container)
        let budgets = BudgetRepository(container: container)
        var now = tokyo("2026-11-29")   // Sunday: W = 1
        try budgets.setBudget(70_000, for: LedgerMonth(year: 2026, month: 11), now: now)
        let model = LedgerModel(repository: expenses, budgets: budgets, today: { now })
        #expect(model.budgetSummary?.weeklyAllowance?.daysLeftInWeek == 1)
        #expect(model.budgetSummary?.weeklyAllowance?.daysLeftInMonth == 2)

        // Past midnight: Monday 30 November, the last day.
        now = tokyo("2026-11-30")
        model.refreshForCurrentDate()
        #expect(model.budgetSummary?.weeklyAllowance?.fromDayKey == "2026-11-30")
        #expect(model.budgetSummary?.weeklyAllowance?.yen == 70_000, "the last day gets everything left")

        // Into December: the ledger follows to the new month, which has no budget yet.
        now = tokyo("2026-12-01")
        model.refreshForCurrentDate()
        #expect(model.month == LedgerMonth(year: 2026, month: 12))
        #expect(model.budgetSummary?.status == .unset)
        #expect(model.canEditBudget)

        // Browsing a past month is left alone by a refresh.
        model.showPrevious()
        now = tokyo("2026-12-02")
        model.refreshForCurrentDate()
        #expect(model.month == LedgerMonth(year: 2026, month: 11))
        #expect(model.budgetSummary?.weeklyAllowance == nil, "past months have no weekly allowance")
        #expect(model.budgetSummary?.budgetYen == 70_000)
    }
}
