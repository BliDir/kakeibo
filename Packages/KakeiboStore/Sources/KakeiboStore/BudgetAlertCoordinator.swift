import Foundation
import KakeiboCore
import Observation
import SwiftData

/// Runs the 80% / 100% budget alert policy after every committed change and acts on it
/// (v1.1, B-07): stores handled thresholds and notification intents, sends or cancels local
/// notifications, and publishes the in-app banner.
///
/// When it runs:
/// - After every successful save of the shared context (`ModelContext.didSave`): an expense
///   scanned, typed, edited, deleted or moved to another month, or a budget set, changed or
///   removed. A failed save rolls back and posts nothing, so it never raises an alert.
/// - On launch, on foreground and at Tokyo midnight (`reconcile()`).
/// Opening or browsing a month only reads, so it never raises one; only the current Tokyo
/// month is ever evaluated.
///
/// How it stays duplicate-free:
/// - Runs are serialized. A change during a run queues one more run, which reads fresh state.
/// - Each run reads, decides and stores in one step on the main actor with no suspension in
///   between, so a save cannot slip in between the read and the write.
/// - The threshold is stored as handled, and the intent as `pending`, before iOS is asked to
///   show anything. After iOS accepts it the intent becomes `delivered`. If the app stops in
///   between, the next run finds the `pending` intent and sends it once more under the same
///   request ID, so iOS replaces rather than duplicates it.
/// - Handled thresholds never rearm. With alerts off or denied the event is consumed (in-app
///   banner only) and nothing is queued, so turning alerts on later replays nothing.
@MainActor
@Observable
public final class BudgetAlertCoordinator {
    /// The in-app banner for the latest event. The app shows it and calls `dismissBanner()`.
    public struct Banner: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let threshold: BudgetThreshold
        public let month: LedgerMonth
        /// R = B − S when the event was raised (negative when over budget).
        public let remainingYen: Int?
    }

    public private(set) var banner: Banner?

    private let expenses: ExpenseRepository
    private let budgets: BudgetRepository
    private let notifier: BudgetNotifier
    private let now: () -> Date
    private let calendar: Calendar

    private var observer: (any NSObjectProtocol)?
    private var running: Task<Void, Never>?
    private var runAgain = false
    /// True while this coordinator saves its own bookkeeping, so that save does not queue a run.
    private var isWriting = false

    public init(expenses: ExpenseRepository, budgets: BudgetRepository, notifier: BudgetNotifier,
                now: @escaping () -> Date = { Date() }, calendar: Calendar = .kakeibo) {
        self.expenses = expenses
        self.budgets = budgets
        self.notifier = notifier
        self.now = now
        self.calendar = calendar
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: expenses.context, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.committedChange() }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Re-checks the current month: on launch, on foreground and at Tokyo midnight. Also
    /// retries a notification that was decided but not confirmed, and cancels ones for a month
    /// that has ended.
    public func reconcile() {
        requestRun()
    }

    public func dismissBanner() {
        banner = nil
    }

    /// Waits until no run is going or queued. For tests.
    public func waitUntilIdle() async {
        while let running { await running.value }
    }

    // MARK: - Runs

    private func committedChange() {
        guard !isWriting else { return }
        requestRun()
    }

    private func requestRun() {
        guard running == nil else {
            runAgain = true
            return
        }
        running = Task { [weak self] in
            guard let self else { return }
            repeat {
                runAgain = false
                await runOnce()
            } while runAgain
            running = nil
        }
    }

    private func runOnce() async {
        // The only suspension before deciding: the permission can change in iOS Settings.
        await notifier.refreshAuthorization()
        guard let plan = decideAndStore() else { return }

        for (month, thresholds) in plan.cancel {
            await notifier.cancelPending(thresholds, for: month)
        }
        for threshold in plan.send.sorted() {
            let result = await notifier.send(threshold, for: plan.month)
            switch result {
            case .handedToSystem: store(.delivered, plan.month, threshold)
            case .notAllowed: store(.cancelled, plan.month, threshold)   // no backlog
            case .failed: break   // stays pending; the next run tries once more
            }
        }
    }

    /// What one run does to iOS after storing its decision.
    private struct Plan {
        var month: LedgerMonth
        var send: Set<BudgetThreshold> = []
        var cancel: [(LedgerMonth, Set<BudgetThreshold>)] = []
    }

    /// Reads, decides and stores, all without suspending. Nil if the store could not be read
    /// or written: nothing is sent then, and the next run starts again from stored state.
    private func decideAndStore() -> Plan? {
        let date = now()
        let month = LedgerMonth(containing: date)
        isWriting = true
        defer { isWriting = false }
        do {
            // `budget(for:)` may apply the future-month template (a write of its own).
            let budget = try budgets.budget(for: month, now: date)
            let spent = MonthSpend.total(try expenses.expenses(inMonth: month.key))
            let handled = try budgets.handledThresholds(for: month)
            let pendingIntents = try budgets.intents(in: .pending)
            let pendingThisMonth = Set(pendingIntents.filter { $0.monthKey == month.key }.compactMap(\.threshold))

            let decision = BudgetAlertPolicy.evaluate(.init(
                month: month, budget: budget, spentYen: spent, handled: handled,
                pending: pendingThisMonth, notificationsAllowed: notifier.canSend,
                now: date, calendar: calendar
            ))

            var plan = Plan(month: month)
            var changes: [BudgetRepository.IntentChange] = []
            // A month that has ended: cancel its pending alerts, with no catch-up.
            for intent in pendingIntents where BudgetAlertPolicy.isStale(intentMonthKey: intent.monthKey, now: date, calendar: calendar) {
                guard let old = LedgerMonth(dayKey: intent.monthKey + "-01"), let threshold = intent.threshold else { continue }
                changes.append(.init(old, threshold, .cancelled))
                plan.cancel.append((old, [threshold]))
            }
            // This month's pending alerts that no longer apply.
            for threshold in decision.cancelPending.sorted() {
                changes.append(.init(month, threshold, .cancelled))
            }
            if !decision.cancelPending.isEmpty { plan.cancel.append((month, decision.cancelPending)) }
            // Pending alerts that still apply (an earlier run stopped before iOS confirmed):
            // send once more if allowed, otherwise drop them rather than keep a backlog.
            let retry = pendingThisMonth.subtracting(decision.cancelPending)
            var candidates = notifier.canSend ? retry : []
            if let event = decision.event, event.sendNotification {
                changes.append(.init(month, event.threshold, .pending))
                candidates.insert(event.threshold)
            }
            // At most one alert per run, the highest: an unconfirmed 80% retried while spend
            // has reached 100% gives way to 100%, so the two never arrive as a pair.
            if let highest = candidates.max() { plan.send = [highest] }
            for threshold in retry.subtracting(plan.send).sorted() {
                changes.append(.init(month, threshold, .cancelled))
            }
            // Handled thresholds and intents in one save, before iOS is asked for anything.
            try budgets.storeAlertDecision(markHandled: decision.markHandled, for: month, intents: changes, now: date)

            if let event = decision.event {
                let summary = BudgetSummary(month: month, budget: budget, spentYen: spent, now: date)
                banner = Banner(id: UUID(), threshold: event.threshold, month: month, remainingYen: summary.remainingYen)
            }
            return plan
        } catch {
            return nil
        }
    }

    private func store(_ state: BudgetAlertIntentState, _ month: LedgerMonth, _ threshold: BudgetThreshold) {
        isWriting = true
        defer { isWriting = false }
        _ = try? budgets.recordIntent(for: month, threshold: threshold, state: state, now: now())
    }
}
