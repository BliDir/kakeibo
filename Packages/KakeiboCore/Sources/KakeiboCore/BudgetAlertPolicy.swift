import Foundation

// The 80% and 100% budget alert policy (v1.1, B-03): a pure state machine.
//
// It only decides; it never stores, notifies or reads the clock itself. Callers (B-07) run it
// after a successful saved change (expense saved, edited, deleted or moved; budget set,
// changed or removed) and when reconciling on launch or foreground, then store
// `markHandled` and act on `event` and `cancelPending`.
//
// Rules (Kakeibo iOS v1.1 release plan, proposed defaults):
// - Thresholds are exact: S / B ≥ 0.8 and S / B ≥ 1.0, compared in whole-yen integers.
// - Only the current Tokyo month can raise an alert; viewing a past month never does.
// - At most one event per threshold per month. If one change reaches 100% first, only 100%
//   is raised and both thresholds are marked handled. If 80% was already raised, 100% can still
//   be raised once.
// - Falling below a threshold (deletion, refund, raised budget) never rearms it. A lowered or
//   new budget can raise the highest threshold that is now reached and not yet handled.
// - Handled thresholds are consumed whether or not a system notification can be sent: with
//   notifications off or denied, nothing is queued and nothing replays when they are turned on.
//   The in-app warning (`reached`) always reflects the current state.

/// One alert to raise now.
public struct BudgetAlertEvent: Sendable, Equatable {
    public let threshold: BudgetThreshold
    /// Also send a local notification. False when the user has not turned alerts on, or the
    /// system denied permission. The in-app banner is shown either way.
    public let sendNotification: Bool
}

public enum BudgetAlertPolicy {
    /// What the caller knows when it evaluates.
    public struct Input: Sendable {
        public var month: LedgerMonth
        public var budget: MonthlyBudget
        /// S for the month, as `MonthSpend.total` gives it (nil when out of range).
        public var spentYen: Int?
        /// Thresholds already handled this month (stored, B-02). Never shrinks.
        public var handled: Set<BudgetThreshold>
        /// Thresholds with a notification still pending for this month.
        public var pending: Set<BudgetThreshold>
        /// The user turned alerts on and the system allows notifications.
        public var notificationsAllowed: Bool
        public var now: Date
        public var calendar: Calendar

        public init(month: LedgerMonth, budget: MonthlyBudget, spentYen: Int?,
                    handled: Set<BudgetThreshold>, pending: Set<BudgetThreshold> = [],
                    notificationsAllowed: Bool, now: Date, calendar: Calendar = .kakeibo) {
            self.month = month
            self.budget = budget
            self.spentYen = spentYen
            self.handled = handled
            self.pending = pending
            self.notificationsAllowed = notificationsAllowed
            self.now = now
            self.calendar = calendar
        }
    }

    public struct Decision: Sendable, Equatable {
        /// Thresholds spend has reached right now: the in-app warning, whatever the history.
        public var reached: Set<BudgetThreshold>
        /// The alert to raise now, if any (at most one).
        public var event: BudgetAlertEvent?
        /// Thresholds to record as handled for the month. Only ever adds.
        public var markHandled: Set<BudgetThreshold>
        /// Pending notifications for this month that no longer apply: cancel them (they stay handled).
        public var cancelPending: Set<BudgetThreshold>

        public static let none = Decision(reached: [], event: nil, markHandled: [], cancelPending: [])
    }

    public static func evaluate(_ input: Input) -> Decision {
        guard let budgetYen = input.budget.yen, let spent = input.spentYen else {
            // No usable budget: nothing is reached, and any pending notification no longer applies.
            return Decision(reached: [], event: nil, markHandled: [], cancelPending: input.pending)
        }
        let reached = reachedThresholds(spentYen: spent, budgetYen: budgetYen)
        let cancel = input.pending.subtracting(reached)

        // Only the current Tokyo month raises alerts.
        guard isCurrentMonth(input.month, now: input.now, calendar: input.calendar) else {
            return Decision(reached: reached, event: nil, markHandled: [], cancelPending: cancel)
        }

        let newlyReached = reached.subtracting(input.handled)
        guard let highest = newlyReached.max() else {
            return Decision(reached: reached, event: nil, markHandled: [], cancelPending: cancel)
        }
        // Raising the highest also consumes the lower ones: no 80% and 100% pair at once.
        return Decision(
            reached: reached,
            event: BudgetAlertEvent(threshold: highest, sendNotification: input.notificationsAllowed),
            markHandled: newlyReached,
            cancelPending: cancel
        )
    }

    /// Thresholds reached by spend S against budget B, compared exactly:
    /// 80% when 5·S ≥ 4·B, 100% when S ≥ B. Negative or zero spend reaches nothing.
    public static func reachedThresholds(spentYen s: Int, budgetYen b: Int) -> Set<BudgetThreshold> {
        guard b > 0, s > 0 else { return [] }
        var reached: Set<BudgetThreshold> = []
        if atLeast(s, numerator: 4, denominator: 5, of: b) { reached.insert(.eighty) }
        if s >= b { reached.insert(.hundred) }
        return reached
    }

    /// True when a pending notification belongs to a month other than the current one:
    /// cancel it, with no catch-up for an old month.
    public static func isStale(intentMonthKey: String, now: Date, calendar: Calendar = .kakeibo) -> Bool {
        intentMonthKey != monthKey(of: now, calendar: calendar)
    }

    // MARK: - Helpers

    /// s ≥ (numerator / denominator) · b, as denominator · s ≥ numerator · b, without overflow.
    /// s, b > 0; numerator · b fits because b ≤ `MonthlyBudget.maximumYen` in practice, and is
    /// checked anyway.
    static func atLeast(_ s: Int, numerator: Int, denominator: Int, of b: Int) -> Bool {
        let (left, leftOverflow) = s.multipliedReportingOverflow(by: denominator)
        let (right, rightOverflow) = b.multipliedReportingOverflow(by: numerator)
        switch (leftOverflow, rightOverflow) {
        case (false, false): return left >= right
        case (true, false): return true     // denominator · s is beyond Int, so above any fitting right side
        case (false, true): return false
        case (true, true):
            // Both huge: compare the quotients, then the remainders.
            let (sq, sr) = s.quotientAndRemainder(dividingBy: numerator)
            let (bq, br) = b.quotientAndRemainder(dividingBy: denominator)
            if sq != bq { return sq > bq }
            return sr * denominator >= br * numerator
        }
    }

    private static func isCurrentMonth(_ month: LedgerMonth, now: Date, calendar: Calendar) -> Bool {
        let today = calendar.dateComponents([.year, .month], from: now)
        return today.year == month.year && today.month == month.month
    }

    private static func monthKey(of date: Date, calendar: Calendar) -> String {
        let today = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", today.year ?? 0, today.month ?? 0)
    }
}
