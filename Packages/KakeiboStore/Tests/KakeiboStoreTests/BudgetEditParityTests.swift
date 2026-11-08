import Foundation
import KakeiboCore
import SwiftData
import Testing
@testable import KakeiboStore

/// BI-08 regression: a budget edit from the review sheet (BI-05) and the same edit from the
/// budget sheet (B-04) leave the same budget, progress, weekly guidance and 80%/100% alerts.
@MainActor
@Suite struct BudgetEditParityTests {
    static let today = Date(timeIntervalSince1970: 1_795_143_600) // Friday 2026-11-20 12:00 Tokyo
    static let november = LedgerMonth(year: 2026, month: 11)
    static let december = LedgerMonth(year: 2026, month: 12)
    static let inDecember = Calendar.kakeibo.date(from: DateComponents(year: 2026, month: 12, day: 2, hour: 12))!

    /// One app's worth of services: ledger, budgets, alerts and a fake notification center.
    @MainActor
    final class World {
        let expenses: ExpenseRepository
        let budgets: BudgetRepository
        let center = InMemoryNotificationCenter(status: .allowed)
        let coordinator: BudgetAlertCoordinator
        let ledger: LedgerModel

        init(template: Int? = nil) throws {
            let container = try KakeiboStore.makeContainer(inMemory: true)
            expenses = ExpenseRepository(container: container)
            budgets = BudgetRepository(context: expenses.context)
            let settings = AppSettings(defaults: UserDefaults(suiteName: "BudgetEditParityTests-\(UUID().uuidString)")!)
            settings.budgetAlertsEnabled = true
            let notifier = BudgetNotifier(center: center, settings: settings) { _ in .init(title: "t", body: "b") }
            coordinator = BudgetAlertCoordinator(expenses: expenses, budgets: budgets, notifier: notifier,
                                                 now: { BudgetEditParityTests.today })
            ledger = LedgerModel(repository: expenses, budgets: budgets, today: { BudgetEditParityTests.today })
            // ¥42,000 spent against a ¥60,000 budget (70%: no alert yet).
            for (day, yen) in [("2026-11-03", 30_000), ("2026-11-10", 8_000), ("2026-11-18", 4_000)] {
                _ = try expenses.create(from: ReceiptDraft(storeName: "店", dayKey: day, totalYen: yen),
                                        source: .manual, now: BudgetEditParityTests.today)
            }
            try budgets.setBudget(60_000, for: BudgetEditParityTests.november, now: BudgetEditParityTests.today)
            if let template { try budgets.setTemplate(amountYen: template, now: BudgetEditParityTests.today) }
        }

        func settle() async {
            for _ in 0..<2 {
                for _ in 0..<5 { await Task.yield() }
                await coordinator.waitUntilIdle()
            }
        }

        /// What the user can see or be told after the edit.
        struct Outcome: Equatable {
            let budget: MonthlyBudget
            let summary: BudgetSummary?
            let handled: Set<BudgetThreshold>
            let delivered: [String]
            let bannerThreshold: BudgetThreshold?
            let bannerRemaining: Int?
            let templateAmount: Int?
            let templateStart: String?
            let december: MonthlyBudget
        }

        func outcome() async throws -> Outcome {
            let november = BudgetEditParityTests.november
            let template = try budgets.template()
            let delivered = await center.delivered
            return Outcome(
                budget: try budgets.budget(for: november, now: BudgetEditParityTests.today),
                summary: ledger.budgetSummary,
                handled: try budgets.handledThresholds(for: november),
                delivered: delivered,
                bannerThreshold: coordinator.banner?.threshold,
                bannerRemaining: coordinator.banner?.remainingYen,
                templateAmount: template?.amountYen,
                templateStart: template?.startMonthKey,
                // Read last: applying the template writes December's row.
                december: try budgets.budget(for: BudgetEditParityTests.december, now: BudgetEditParityTests.inDecember)
            )
        }
    }

    private func editWithBudgetSheet(_ world: World, _ yen: Int, future: Bool) async throws {
        let form = try BudgetForm(repository: world.budgets, month: Self.november, now: Self.today)
        form.amountText = String(yen)
        form.useForFutureMonths = future
        #expect(form.save(now: Self.today))
        await world.settle()
    }

    private func editWithReview(_ world: World, _ yen: Int, future: Bool) async throws {
        let form = try #require(world.ledger.makeBudgetReview())
        form.choice = future ? .fromThisMonthOn : .thisMonthOnly
        form.amountText = String(yen)
        #expect(form.confirm())
        await world.settle()
    }

    /// ¥50,000 crosses 80%; ¥40,000 jumps past 100% (only the 100% alert); ¥100,000 raises none.
    @Test(arguments: [50_000, 40_000, 100_000], [false, true])
    func reviewAndBudgetSheetEditsMatch(yen: Int, future: Bool) async throws {
        let sheet = try World()
        let review = try World()
        await sheet.settle()
        await review.settle()

        try await editWithBudgetSheet(sheet, yen, future: future)
        try await editWithReview(review, yen, future: future)

        let expected = try await sheet.outcome()
        #expect(try await review.outcome() == expected)
        #expect(expected.budget == .yen(yen))
        #expect(expected.summary?.budgetYen == yen)
        #expect(expected.summary?.weeklyAllowance != nil)
        switch yen {
        case 50_000: #expect(expected.handled == [.eighty])
        case 40_000: #expect(expected.handled == [.eighty, .hundred])
        default: #expect(expected.handled.isEmpty)
        }
        #expect(expected.december == (future ? .yen(yen) : .unset))
    }

    /// The one intended difference: B-04's switch turned off stops a saved future-months amount,
    /// while the review's "This month only" says future months are not changed and keeps it.
    @Test func thisMonthOnlyKeepsAnExistingFutureAmount() async throws {
        let sheet = try World(template: 55_000)
        let review = try World(template: 55_000)
        try await editWithBudgetSheet(sheet, 50_000, future: false)
        try await editWithReview(review, 50_000, future: false)

        let fromSheet = try await sheet.outcome()
        let fromReview = try await review.outcome()
        #expect(fromSheet.budget == fromReview.budget)
        #expect(fromSheet.summary == fromReview.summary)
        #expect(fromSheet.handled == fromReview.handled)
        #expect(fromSheet.delivered == fromReview.delivered)
        #expect(fromSheet.templateAmount == nil)
        #expect(fromReview.templateAmount == 55_000)
        #expect(fromReview.december == .yen(55_000))
    }
}
