import Foundation
import KakeiboCore
import SwiftData
import Testing
@testable import KakeiboStore

private struct SaveFailed: Error {}

/// 12:00 Tokyo on a day.
private func tokyo(_ dayKey: String) -> Date {
    let p = dayKey.split(separator: "-").map { Int($0)! }
    return Calendar.kakeibo.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!
}

@MainActor
@Suite struct BudgetRepositoryTests {
    let container: ModelContainer
    let repo: BudgetRepository
    let expenses: ExpenseRepository

    static let nov = LedgerMonth(year: 2026, month: 11)
    static let dec = LedgerMonth(year: 2026, month: 12)
    static let jan = LedgerMonth(year: 2027, month: 1)
    static let feb = LedgerMonth(year: 2027, month: 2)
    static let novDay = tokyo("2026-11-05")

    init() throws {
        container = try KakeiboStore.makeContainer(inMemory: true)
        repo = BudgetRepository(container: container)
        expenses = ExpenseRepository(container: container)
    }

    private func rows() throws -> [BudgetMonth] { try container.mainContext.fetch(FetchDescriptor<BudgetMonth>()) }

    // MARK: Current month: create, edit, remove

    @Test func startsWithNoBudget() throws {
        #expect(try repo.budget(for: Self.nov, now: Self.novDay) == .unset)
        #expect(try rows().isEmpty, "reading does not create a row without a template")
    }

    @Test func createEditAndRemoveTheCurrentMonth() throws {
        try repo.setBudget(100_000, for: Self.nov, now: Self.novDay)
        #expect(try repo.budget(for: Self.nov, now: Self.novDay) == .yen(100_000))

        try repo.setBudget(120_000, for: Self.nov, now: Self.novDay)
        #expect(try repo.budget(for: Self.nov, now: Self.novDay) == .yen(120_000))
        #expect(try rows().count == 1)

        try repo.removeBudget(for: Self.nov, now: Self.novDay)
        #expect(try repo.budget(for: Self.nov, now: Self.novDay) == .unset)
        #expect(try rows().count == 1, "the month's row stays for its alert history")
    }

    @Test func removingKeepsReceipts() throws {
        try expenses.create(from: ReceiptDraft(dayKey: "2026-11-03", totalYen: 1_310), source: .manual)
        try repo.setBudget(50_000, for: Self.nov, now: Self.novDay)
        try repo.removeBudget(for: Self.nov, now: Self.novDay)
        #expect(try expenses.expenses(inMonth: Self.nov.key).map(\.totalYen) == [1_310])
    }

    @Test func invalidAmountsAreRefused() throws {
        #expect(throws: BudgetRepository.Error.invalidBudget(.notPositive)) {
            try repo.setBudget(0, for: Self.nov, now: Self.novDay)
        }
        #expect(throws: BudgetRepository.Error.invalidBudget(.tooLarge)) {
            try repo.setBudget(MonthlyBudget.maximumYen + 1, for: Self.nov, now: Self.novDay)
        }
        #expect(try rows().isEmpty)
    }

    // MARK: Historical months

    @Test func pastMonthsAreReadOnly() throws {
        try repo.setBudget(90_000, for: Self.nov, now: Self.novDay)
        let inDecember = tokyo("2026-12-10")
        #expect(try repo.budget(for: Self.nov, now: inDecember) == .yen(90_000), "still readable for comparison")
        #expect(throws: BudgetRepository.Error.readOnlyMonth("2026-11")) {
            try repo.setBudget(95_000, for: Self.nov, now: inDecember)
        }
        #expect(throws: BudgetRepository.Error.readOnlyMonth("2026-11")) {
            try repo.removeBudget(for: Self.nov, now: inDecember)
        }
        #expect(try repo.budget(for: Self.nov, now: inDecember) == .yen(90_000))
    }

    @Test func futureMonthsCannotBeSetAhead() {
        #expect(throws: BudgetRepository.Error.readOnlyMonth("2026-12")) {
            try repo.setBudget(90_000, for: Self.dec, now: Self.novDay)
        }
    }

    // MARK: Unique months

    @Test func oneRowPerMonth() throws {
        for amount in [10_000, 20_000, 30_000] {
            try repo.setBudget(amount, for: Self.nov, now: Self.novDay)
        }
        try repo.markHandled([.eighty], for: Self.nov, now: Self.novDay)
        try repo.removeBudget(for: Self.nov, now: Self.novDay)
        try repo.setBudget(40_000, for: Self.nov, now: Self.novDay)
        #expect(try rows().map(\.monthKey) == ["2026-11"])
    }

    @Test func storeLevelUniquenessBacksTheRepository() throws {
        // Even a direct second insert of the same month leaves one row (SwiftData's unique attribute).
        let context = container.mainContext
        context.insert(BudgetMonth(monthKey: "2026-11", budgetYen: 1_000, createdAt: Self.novDay, updatedAt: Self.novDay))
        try context.save()
        context.insert(BudgetMonth(monthKey: "2026-11", budgetYen: 2_000, createdAt: Self.novDay, updatedAt: Self.novDay))
        try context.save()
        #expect(try rows().count == 1)
    }

    // MARK: Template

    @Test func templateIsOffByDefaultAndStartsNextMonth() throws {
        #expect(try repo.template() == nil)
        try repo.setTemplate(amountYen: 100_000, now: Self.novDay)
        #expect(try repo.template()?.startMonthKey == "2026-12")
        // The current month is not changed by turning the template on.
        #expect(try repo.budget(for: Self.nov, now: Self.novDay) == .unset)
    }

    @Test func templateAppliesLazilyToNewMonthsOnly() throws {
        try repo.setBudget(80_000, for: Self.nov, now: Self.novDay)
        try repo.setTemplate(amountYen: 100_000, now: Self.novDay)

        // December: nothing until December is read while it is the current month.
        #expect(try repo.row(for: Self.dec) == nil)
        #expect(try repo.budget(for: Self.dec, now: Self.novDay) == .unset, "not applied ahead of time")
        #expect(try repo.row(for: Self.dec) == nil)
        let december = tokyo("2026-12-01")
        #expect(try repo.budget(for: Self.dec, now: december) == .yen(100_000))
        #expect(try repo.row(for: Self.dec)?.appliedFromTemplate == true)

        // November keeps its own budget.
        #expect(try repo.budget(for: Self.nov, now: december) == .yen(80_000))

        // Changing the template in December changes neither December nor November.
        try repo.setTemplate(amountYen: 120_000, now: december)
        #expect(try repo.template()?.startMonthKey == "2027-01")
        #expect(try repo.budget(for: Self.dec, now: december) == .yen(100_000))
        #expect(try repo.budget(for: Self.jan, now: tokyo("2027-01-03")) == .yen(120_000))
    }

    @Test func pastMonthsWithoutABudgetNeverGetTheTemplate() throws {
        try repo.setTemplate(amountYen: 100_000, now: Self.novDay)
        // December went by without the app being opened; in January it is read as history.
        #expect(try repo.budget(for: Self.dec, now: tokyo("2027-01-10")) == .unset)
        #expect(try repo.row(for: Self.dec) == nil)
    }

    @Test func disablingAffectsFutureMonthsOnly() throws {
        try repo.setTemplate(amountYen: 100_000, now: Self.novDay)
        let december = tokyo("2026-12-02")
        #expect(try repo.budget(for: Self.dec, now: december) == .yen(100_000))
        try repo.setTemplate(amountYen: nil, now: december)
        #expect(try repo.template() == nil)
        #expect(try repo.budget(for: Self.dec, now: december) == .yen(100_000), "existing month keeps its budget")
        #expect(try repo.budget(for: Self.jan, now: tokyo("2027-01-02")) == .unset)
        try repo.setTemplate(amountYen: nil, now: december)   // turning off twice is fine
    }

    @Test func removedMonthIsNotRefilledByTheTemplate() throws {
        try repo.setTemplate(amountYen: 100_000, now: Self.novDay)
        let december = tokyo("2026-12-02")
        #expect(try repo.budget(for: Self.dec, now: december) == .yen(100_000))
        try repo.removeBudget(for: Self.dec, now: december)
        #expect(try repo.budget(for: Self.dec, now: december) == .unset)
        #expect(try repo.budget(for: Self.dec, now: tokyo("2026-12-20")) == .unset)
    }

    @Test func removingBeforeTheTemplateAppliesBlocksIt() throws {
        try repo.setTemplate(amountYen: 100_000, now: Self.novDay)
        // Removing in a month that has no row yet records it, so the template stays out.
        try repo.removeBudget(for: Self.dec, now: tokyo("2026-12-01"))
        #expect(try repo.budget(for: Self.dec, now: tokyo("2026-12-01")) == .unset)
    }

    @Test func templateAmountIsValidated() throws {
        #expect(throws: BudgetRepository.Error.invalidBudget(.notPositive)) {
            try repo.setTemplate(amountYen: -1, now: Self.novDay)
        }
        #expect(try repo.template() == nil)
    }

    // MARK: Alert history

    @Test func removeAndReAddKeepsHandledThresholds() throws {
        try repo.setBudget(50_000, for: Self.nov, now: Self.novDay)
        try repo.markHandled([.eighty], for: Self.nov, now: Self.novDay)
        try repo.recordIntent(for: Self.nov, threshold: .eighty, state: .delivered, now: Self.novDay)

        try repo.removeBudget(for: Self.nov, now: Self.novDay)
        #expect(try repo.handledThresholds(for: Self.nov) == [.eighty])
        try repo.setBudget(50_000, for: Self.nov, now: Self.novDay)
        #expect(try repo.handledThresholds(for: Self.nov) == [.eighty], "re-adding does not reset alerts")
        #expect(try repo.intent(for: Self.nov, threshold: .eighty)?.state == .delivered)

        try repo.markHandled([.hundred], for: Self.nov, now: Self.novDay)
        #expect(try repo.handledThresholds(for: Self.nov) == [.eighty, .hundred])
        try repo.markHandled([], for: Self.nov, now: Self.novDay)
        #expect(try repo.handledThresholds(for: Self.nov) == [.eighty, .hundred], "never un-marked")
    }

    @Test func monthsHaveIndependentAlertState() throws {
        try repo.markHandled([.eighty, .hundred], for: Self.nov, now: Self.novDay)
        #expect(try repo.handledThresholds(for: Self.dec).isEmpty)
    }

    @Test func intentsHaveStableIDsAndOneRowEach() throws {
        let first = try repo.recordIntent(for: Self.nov, threshold: .hundred, state: .pending, now: Self.novDay)
        #expect(first.requestID == "budget-2026-11-100")
        try repo.recordIntent(for: Self.nov, threshold: .hundred, state: .pending, now: Self.novDay)
        try repo.recordIntent(for: Self.nov, threshold: .eighty, state: .cancelled, now: Self.novDay)
        #expect(try container.mainContext.fetch(FetchDescriptor<BudgetAlertIntent>()).count == 2)
        #expect(try repo.intents(in: .pending).map(\.requestID) == ["budget-2026-11-100"])

        try repo.recordIntent(for: Self.nov, threshold: .hundred, state: .delivered, now: Self.novDay)
        #expect(try repo.intents(in: .pending).isEmpty)
        #expect(try repo.intent(for: Self.nov, threshold: .hundred)?.threshold == .hundred)
    }

    // MARK: Failed writes roll back

    @Test func failedSaveLeavesNothingBehind() throws {
        try repo.setBudget(50_000, for: Self.nov, now: Self.novDay)
        try repo.markHandled([.eighty], for: Self.nov, now: Self.novDay)
        repo.beforeSave = { throw SaveFailed() }

        #expect(throws: SaveFailed.self) { try repo.setBudget(70_000, for: Self.nov, now: Self.novDay) }
        #expect(throws: SaveFailed.self) { try repo.removeBudget(for: Self.nov, now: Self.novDay) }
        #expect(throws: SaveFailed.self) { try repo.setTemplate(amountYen: 90_000, now: Self.novDay) }
        #expect(throws: SaveFailed.self) { try repo.markHandled([.hundred], for: Self.nov, now: Self.novDay) }
        #expect(throws: SaveFailed.self) {
            try repo.recordIntent(for: Self.nov, threshold: .hundred, state: .pending, now: Self.novDay)
        }

        repo.beforeSave = nil
        #expect(try repo.budget(for: Self.nov, now: Self.novDay) == .yen(50_000))
        #expect(try repo.handledThresholds(for: Self.nov) == [.eighty])
        #expect(try repo.template() == nil)
        #expect(try repo.intent(for: Self.nov, threshold: .hundred) == nil)
        #expect(try rows().count == 1)
    }

    @Test func failedTemplateApplicationIsNotKept() throws {
        try repo.setTemplate(amountYen: 100_000, now: Self.novDay)
        repo.beforeSave = { throw SaveFailed() }
        #expect(throws: SaveFailed.self) { try repo.budget(for: Self.dec, now: tokyo("2026-12-01")) }
        repo.beforeSave = nil
        #expect(try repo.row(for: Self.dec) == nil)
        #expect(try repo.budget(for: Self.dec, now: tokyo("2026-12-01")) == .yen(100_000), "applies on the next read")
    }
}

/// Budgets, the template and alert state survive closing and reopening the store.
@MainActor
@Suite struct BudgetPersistenceTests {
    @Test func relaunchKeepsEverything() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BudgetRelaunch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Kakeibo.store")
        let nov = LedgerMonth(year: 2026, month: 11)
        let now = tokyo("2026-11-05")

        do {
            let repo = BudgetRepository(container: try KakeiboStore.makeContainer(url: url))
            try repo.setBudget(75_000, for: nov, now: now)
            try repo.setTemplate(amountYen: 80_000, now: now)
            try repo.markHandled([.eighty], for: nov, now: now)
            try repo.recordIntent(for: nov, threshold: .eighty, state: .pending, now: now)
        }

        let repo = BudgetRepository(container: try KakeiboStore.makeContainer(url: url))
        #expect(try repo.budget(for: nov, now: now) == .yen(75_000))
        #expect(try repo.template()?.amountYen == 80_000)
        #expect(try repo.template()?.startMonthKey == "2026-12")
        #expect(try repo.handledThresholds(for: nov) == [.eighty])
        #expect(try repo.intents(in: .pending).map(\.requestID) == ["budget-2026-11-80"])
    }
}
