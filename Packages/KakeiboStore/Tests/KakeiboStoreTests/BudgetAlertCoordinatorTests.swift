import Foundation
import KakeiboCore
import SwiftData
import Testing
@testable import KakeiboStore

/// B-07: alert evaluation wired to committed changes, stored state and notifications.
@MainActor
@Suite struct BudgetAlertCoordinatorTests {
    final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    struct SaveFailed: Error {}

    /// 2026-11-10 12:00 Tokyo.
    static func tokyo(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        Calendar.kakeibo.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    let november = LedgerMonth(year: 2026, month: 11)
    let container: ModelContainer
    let expenses: ExpenseRepository
    let budgets: BudgetRepository
    let center: InMemoryNotificationCenter
    let settings: AppSettings
    let notifier: BudgetNotifier
    let clock = Clock(Self.tokyo(2026, 11, 10))
    let coordinator: BudgetAlertCoordinator

    init() throws {
        container = try KakeiboStore.makeContainer(inMemory: true)
        expenses = ExpenseRepository(container: container)
        budgets = BudgetRepository(container: container)
        center = InMemoryNotificationCenter(status: .allowed)
        settings = AppSettings(defaults: UserDefaults(suiteName: "BudgetAlertCoordinatorTests-\(UUID().uuidString)")!)
        settings.budgetAlertsEnabled = true
        notifier = BudgetNotifier(center: center, settings: settings) { _ in BudgetNotificationCopy(title: "t", body: "b") }
        let clock = clock
        coordinator = BudgetAlertCoordinator(expenses: expenses, budgets: budgets, notifier: notifier, now: { clock.now })
    }

    // MARK: Helpers

    /// Lets the save notification arrive, then waits for every run to finish.
    private func settle() async {
        for _ in 0..<2 {
            for _ in 0..<5 { await Task.yield() }
            await coordinator.waitUntilIdle()
        }
    }

    @discardableResult
    private func spend(_ yen: Int, on day: String = "2026-11-10") async throws -> Expense {
        let expense = try expenses.create(from: ReceiptDraft(storeName: "店", dayKey: day, totalYen: yen),
                                          source: .manual, now: clock.now)
        await settle()
        return expense
    }

    private func setBudget(_ yen: Int) async throws {
        try budgets.setBudget(yen, for: LedgerMonth(containing: clock.now), now: clock.now)
        await settle()
    }

    private func sent() async -> [String] { await center.added }

    private func state(_ threshold: BudgetThreshold, _ month: LedgerMonth? = nil) throws -> BudgetAlertIntentState? {
        try budgets.intent(for: month ?? november, threshold: threshold)?.state
    }

    /// Takes the banner, as the app does when the user dismisses it.
    private func takeBanner() -> BudgetThreshold? {
        defer { coordinator.dismissBanner() }
        return coordinator.banner?.threshold
    }

    // MARK: Exact crossings

    @Test func oneYenBelowEightyRaisesNothingThenTheCrossingRaisesOnce() async throws {
        try await setBudget(10_000)
        try await spend(7_999)
        #expect(coordinator.banner == nil)
        #expect(await sent().isEmpty)

        try await spend(1)   // exactly 80%
        #expect(takeBanner() == .eighty)
        #expect(await sent() == ["budget-2026-11-80"])
        #expect(try state(.eighty) == .delivered)
        #expect(try budgets.handledThresholds(for: november) == [.eighty])

        try await spend(1_999)   // 99.99%: nothing new
        #expect(coordinator.banner == nil)
        try await spend(1)       // exactly 100%
        #expect(takeBanner() == .hundred)
        #expect(await sent() == ["budget-2026-11-80", "budget-2026-11-100"])
    }

    @Test func jumpingStraightToHundredRaisesOnlyHundred() async throws {
        try await setBudget(10_000)
        try await spend(12_000)
        #expect(takeBanner() == .hundred)
        #expect(await sent() == ["budget-2026-11-100"])
        #expect(try budgets.handledThresholds(for: november) == [.eighty, .hundred])
        #expect(try state(.eighty) == nil, "80% was consumed, never sent")
    }

    @Test func bannerCarriesWhatIsLeftOrOver() async throws {
        try await setBudget(10_000)
        try await spend(8_500)
        #expect(coordinator.banner?.remainingYen == 1_500)
        coordinator.dismissBanner()
        try await spend(2_000)
        #expect(coordinator.banner?.remainingYen == -500)
        #expect(coordinator.banner?.month == november)
    }

    // MARK: Failed and rapid saves

    @Test func aFailedSaveRaisesNothing() async throws {
        try await setBudget(10_000)
        expenses.beforeSave = { throw SaveFailed() }
        #expect(throws: SaveFailed.self) {
            try expenses.create(from: ReceiptDraft(storeName: "店", dayKey: "2026-11-10", totalYen: 9_000), source: .manual)
        }
        await settle()
        #expect(coordinator.banner == nil)
        #expect(await sent().isEmpty)
        #expect(try budgets.handledThresholds(for: november).isEmpty)
        #expect(try expenses.expenses(inMonth: november.key).isEmpty, "rolled back")

        // The next successful save is evaluated normally.
        expenses.beforeSave = nil
        try await spend(9_000)
        #expect(takeBanner() == .eighty)
    }

    @Test func rapidSavesSendEachThresholdOnce() async throws {
        try await setBudget(10_000)
        for _ in 0..<6 {
            try expenses.create(from: ReceiptDraft(storeName: "店", dayKey: "2026-11-10", totalYen: 2_000), source: .manual)
        }
        await settle()
        let ids = await sent()
        #expect(Set(ids) == ["budget-2026-11-80", "budget-2026-11-100"] || ids == ["budget-2026-11-100"])
        #expect(ids.count == Set(ids).count, "no repeats: \(ids)")
        // More saves and reconciliations change nothing.
        try await spend(500)
        coordinator.reconcile()
        await settle()
        #expect(await sent() == ids)
    }

    // MARK: No rearming

    @Test func deletionAndRefundsDoNotRearm() async throws {
        try await setBudget(10_000)
        let big = try await spend(8_000)
        #expect(takeBanner() == .eighty)

        try expenses.delete(big)
        await settle()
        try await spend(-1_000)        // refund
        try await spend(9_500)          // back above 80%
        #expect(coordinator.banner == nil)
        #expect(await sent() == ["budget-2026-11-80"])
    }

    @Test func removingAndReAddingTheBudgetDoesNotReset() async throws {
        try await setBudget(10_000)
        try await spend(8_000)
        #expect(takeBanner() == .eighty)
        try budgets.removeBudget(for: november, now: clock.now)
        await settle()
        try await setBudget(10_000)
        #expect(coordinator.banner == nil)
        #expect(await sent() == ["budget-2026-11-80"])
    }

    @Test func aNewOrLoweredBudgetCanRaiseTheHighestReached() async throws {
        try await spend(9_000)          // no budget yet
        #expect(coordinator.banner == nil)
        try await setBudget(10_000)     // 90%
        #expect(takeBanner() == .eighty)
        try await setBudget(20_000)     // 45%: nothing
        #expect(coordinator.banner == nil)
        try await setBudget(9_000)      // 100%
        #expect(takeBanner() == .hundred)
        #expect(await sent() == ["budget-2026-11-80", "budget-2026-11-100"])
    }

    @Test func movingAnExpenseIntoThisMonthIsEvaluated() async throws {
        try await setBudget(10_000)
        let old = try await spend(9_000, on: "2026-10-28")
        #expect(coordinator.banner == nil, "last month's spend does not count")
        try expenses.update(old) { $0.dayKey = "2026-11-02" }
        await settle()
        #expect(takeBanner() == .eighty)
        // Moving it out and back does not rearm.
        try expenses.update(old) { $0.dayKey = "2026-10-28" }
        await settle()
        try expenses.update(old) { $0.dayKey = "2026-11-02" }
        await settle()
        #expect(coordinator.banner == nil)
        #expect(await sent() == ["budget-2026-11-80"])
    }

    // MARK: Permission

    @Test func deniedPermissionShowsTheBannerAndQueuesNothing() async throws {
        await center.setStatus(.denied)
        try await setBudget(10_000)
        try await spend(8_000)
        #expect(takeBanner() == .eighty, "in-app banner regardless of permission")
        #expect(await sent().isEmpty)
        #expect(try state(.eighty) == nil, "nothing kept to send later")

        // Allowing later replays nothing.
        await center.setStatus(.allowed)
        coordinator.reconcile()
        await settle()
        #expect(await sent().isEmpty)
        #expect(coordinator.banner == nil)
    }

    @Test func alertsTurnedOffConsumeTheEvent() async throws {
        settings.budgetAlertsEnabled = false
        try await setBudget(10_000)
        try await spend(8_000)
        #expect(takeBanner() == .eighty)
        await notifier.setEnabled(true)
        coordinator.reconcile()
        await settle()
        #expect(await sent().isEmpty)
    }

    @Test func permissionLostBeforeSendingCancelsTheIntent() async throws {
        try await setBudget(10_000)
        // Decided while allowed, stopped before iOS confirmed (as after a crash).
        try budgets.storeAlertDecision(markHandled: [.eighty], for: november,
                                       intents: [.init(november, .eighty, .pending)], now: clock.now)
        try await spend(8_000)
        #expect(await sent() == ["budget-2026-11-80"], "retried while allowed")

        try budgets.storeAlertDecision(markHandled: [.hundred], for: november,
                                       intents: [.init(november, .hundred, .pending)], now: clock.now)
        await center.setStatus(.denied)
        coordinator.reconcile()
        await settle()
        #expect(try state(.hundred) == .cancelled, "no backlog while denied")
        await center.setStatus(.allowed)
        coordinator.reconcile()
        await settle()
        #expect(await sent() == ["budget-2026-11-80"], "and nothing replays later")
    }

    // MARK: Restart and delivery

    @Test func restartDuringDeliverySendsOnceUnderTheSameID() async throws {
        // Before the "crash": a store at 80% whose decision was stored but never confirmed by
        // iOS. Built without a coordinator, as the app was killed before it could send.
        let store = try KakeiboStore.makeContainer(inMemory: true)
        let storeExpenses = ExpenseRepository(container: store)
        let storeBudgets = BudgetRepository(container: store)
        try storeBudgets.setBudget(10_000, for: november, now: clock.now)
        try storeExpenses.create(from: ReceiptDraft(storeName: "店", dayKey: "2026-11-10", totalYen: 8_000), source: .manual)
        try storeBudgets.storeAlertDecision(markHandled: [.eighty], for: november,
                                            intents: [.init(november, .eighty, .pending)], now: clock.now)

        // Relaunch.
        let relaunched = BudgetAlertCoordinator(expenses: storeExpenses, budgets: storeBudgets, notifier: notifier,
                                                now: { [clock] in clock.now })
        relaunched.reconcile()
        await relaunched.waitUntilIdle()
        #expect(await sent() == ["budget-2026-11-80"])
        #expect(try storeBudgets.intent(for: november, threshold: .eighty)?.state == .delivered)
        #expect(relaunched.banner == nil, "already handled: no second banner")

        relaunched.reconcile()
        await relaunched.waitUntilIdle()
        #expect(await sent() == ["budget-2026-11-80"], "not sent again")
    }

    @Test func anUnconfirmedEightyGivesWayWhenHundredIsReached() async throws {
        await center.setFailAdd(true)
        try await setBudget(10_000)
        try await spend(8_000)
        #expect(try state(.eighty) == .pending, "iOS refused it; kept for a retry")
        coordinator.dismissBanner()

        await center.setFailAdd(false)
        try await spend(3_000)   // now over budget
        #expect(takeBanner() == .hundred)
        #expect(await sent() == ["budget-2026-11-100"], "100% only, no 80% + 100% pair")
        #expect(try state(.eighty) == .cancelled)
        #expect(try state(.hundred) == .delivered)
    }

    @Test func aRefusedRequestStaysPendingAndIsRetriedOnce() async throws {
        await center.setFailAdd(true)
        try await setBudget(10_000)
        try await spend(8_000)
        #expect(takeBanner() == .eighty)
        #expect(try state(.eighty) == .pending)

        await center.setFailAdd(false)
        coordinator.reconcile()
        await settle()
        #expect(await sent() == ["budget-2026-11-80"])
        #expect(try state(.eighty) == .delivered)
        coordinator.reconcile()
        await settle()
        #expect(await sent() == ["budget-2026-11-80"])
    }

    @Test func pendingAlertsThatNoLongerApplyAreCancelled() async throws {
        try await setBudget(10_000)
        try await spend(5_000)
        try budgets.storeAlertDecision(markHandled: [.eighty], for: november,
                                       intents: [.init(november, .eighty, .pending)], now: clock.now)
        coordinator.reconcile()
        await settle()
        #expect(try state(.eighty) == .cancelled)
        #expect(await sent().isEmpty)
        // Cancelled stays handled: crossing later raises nothing.
        try await spend(4_000)
        #expect(coordinator.banner == nil)
    }

    // MARK: Months

    @Test func monthRolloverCancelsOldPendingAndStartsFresh() async throws {
        try await setBudget(10_000)
        try await spend(8_000)
        #expect(takeBanner() == .eighty)
        try budgets.storeAlertDecision(markHandled: [.hundred], for: november,
                                       intents: [.init(november, .hundred, .pending)], now: clock.now)

        clock.now = Self.tokyo(2026, 12, 1, hour: 0)
        coordinator.reconcile()
        await settle()
        #expect(try state(.hundred) == .cancelled, "no catch-up for November")
        #expect(coordinator.banner == nil)

        // December has its own thresholds.
        try await setBudget(10_000)
        try await spend(8_000, on: "2026-12-01")
        #expect(takeBanner() == .eighty)
        #expect(await sent() == ["budget-2026-11-80", "budget-2026-12-80"])
    }

    @Test func browsingAPastMonthRaisesNothing() async throws {
        // October was over its budget, and nothing was ever raised for it.
        let october = november.previous
        container.mainContext.insert(BudgetMonth(monthKey: october.key, budgetYen: 5_000, createdAt: clock.now, updatedAt: clock.now))
        try container.mainContext.save()
        try await spend(9_000, on: "2026-10-15")

        let ledger = LedgerModel(repository: expenses, budgets: budgets, today: { [clock] in clock.now })
        ledger.show(october)
        coordinator.reconcile()
        await settle()
        #expect(ledger.budgetSummary?.remainingYen == -4_000)
        #expect(coordinator.banner == nil)
        #expect(await sent().isEmpty)
        #expect(try budgets.handledThresholds(for: october).isEmpty)
    }
}

@MainActor
@Suite struct StoreAlertDecisionTests {
    @Test func storesHandledAndIntentsInOneSave() throws {
        let container = try KakeiboStore.makeContainer(inMemory: true)
        let budgets = BudgetRepository(container: container)
        let month = LedgerMonth(year: 2026, month: 11)
        let now = Date(timeIntervalSince1970: 1_794_000_000)
        try budgets.storeAlertDecision(markHandled: [.eighty], for: month, intents: [
            .init(month, .eighty, .pending),
            .init(month, .eighty, .delivered),   // the later change wins
            .init(month.previous, .hundred, .cancelled),
        ], now: now)
        #expect(try budgets.handledThresholds(for: month) == [.eighty])
        #expect(try budgets.intent(for: month, threshold: .eighty)?.state == .delivered)
        #expect(try budgets.intent(for: month.previous, threshold: .hundred)?.state == .cancelled)
    }

    @Test func aFailedSaveStoresNothing() throws {
        struct Failed: Error {}
        let container = try KakeiboStore.makeContainer(inMemory: true)
        let budgets = BudgetRepository(container: container)
        let month = LedgerMonth(year: 2026, month: 11)
        budgets.beforeSave = { throw Failed() }
        #expect(throws: Failed.self) {
            try budgets.storeAlertDecision(markHandled: [.eighty], for: month,
                                           intents: [.init(month, .eighty, .pending)], now: .now)
        }
        budgets.beforeSave = nil
        #expect(try budgets.handledThresholds(for: month).isEmpty)
        #expect(try budgets.intent(for: month, threshold: .eighty) == nil)
    }
}
