import Foundation
import Testing
@testable import KakeiboCore

private func tokyo(_ dayKey: String) -> Date {
    let p = dayKey.split(separator: "-").map { Int($0)! }
    return Calendar.kakeibo.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!
}

private let nov = LedgerMonth(year: 2026, month: 11)
private let novDay = tokyo("2026-11-05")

/// Evaluates for November on 5 November unless told otherwise.
private func evaluate(budget: MonthlyBudget = .yen(100_000), spent: Int?, handled: Set<BudgetThreshold> = [],
                      pending: Set<BudgetThreshold> = [], allowed: Bool = true,
                      month: LedgerMonth = nov, now: Date = novDay) -> BudgetAlertPolicy.Decision {
    BudgetAlertPolicy.evaluate(.init(month: month, budget: budget, spentYen: spent, handled: handled,
                                     pending: pending, notificationsAllowed: allowed, now: now))
}

@Suite struct BudgetAlertPolicyTests {
    // MARK: Exact thresholds

    @Test func exactlyEightyPercent() {
        let d = evaluate(spent: 80_000)
        #expect(d.reached == [.eighty])
        #expect(d.event == BudgetAlertEvent(threshold: .eighty, sendNotification: true))
        #expect(d.markHandled == [.eighty])
    }

    @Test func oneYenBelowEighty() {
        let d = evaluate(spent: 79_999)
        #expect(d == .none)
    }

    @Test func exactlyOneHundredPercentAfterEighty() {
        let d = evaluate(spent: 100_000, handled: [.eighty])
        #expect(d.reached == [.eighty, .hundred])
        #expect(d.event?.threshold == .hundred)
        #expect(d.markHandled == [.hundred])
    }

    @Test func oneYenBelowOneHundred() {
        let d = evaluate(spent: 99_999, handled: [.eighty])
        #expect(d.reached == [.eighty])
        #expect(d.event == nil)
        #expect(d.markHandled.isEmpty)
    }

    @Test func budgetsThatDoNotDivideEvenly() {
        // 80% of ¥99,999 is ¥79,999.2: ¥79,999 is below, ¥80,000 reaches it.
        #expect(evaluate(budget: .yen(99_999), spent: 79_999).event == nil)
        #expect(evaluate(budget: .yen(99_999), spent: 80_000).event?.threshold == .eighty)
        // 80% of ¥1 is ¥0.8: ¥1 reaches both.
        #expect(evaluate(budget: .yen(1), spent: 1).reached == [.eighty, .hundred])
        // 80% of ¥5 is exactly ¥4.
        #expect(evaluate(budget: .yen(5), spent: 3).reached.isEmpty)
        #expect(evaluate(budget: .yen(5), spent: 4).reached == [.eighty])
    }

    // MARK: Jumping straight to 100%

    @Test func leapToOneHundredRaisesOnlyOneHundred() {
        let d = evaluate(spent: 150_000)
        #expect(d.event?.threshold == .hundred)
        #expect(d.markHandled == [.eighty, .hundred], "80% is consumed, not raised as well")
    }

    // MARK: Repeated evaluation

    @Test func sameStateRaisesNothingTwice() {
        var handled: Set<BudgetThreshold> = []
        var events: [BudgetThreshold] = []
        // Rapid saves pushing spend up, evaluated after each one.
        for spent in [50_000, 81_000, 81_000, 90_000, 101_000, 101_000, 140_000] {
            let d = evaluate(spent: spent, handled: handled)
            if let event = d.event { events.append(event.threshold) }
            handled.formUnion(d.markHandled)
        }
        #expect(events == [.eighty, .hundred])
        #expect(handled == [.eighty, .hundred])
    }

    // MARK: Refunds, deletions and budget changes

    @Test func fallingBelowDoesNotRearm() {
        // 80% raised, then a deletion or refund drops spend, then it rises again.
        var handled: Set<BudgetThreshold> = [.eighty]
        let down = evaluate(spent: 60_000, handled: handled)
        #expect(down.event == nil && down.markHandled.isEmpty)
        #expect(down.reached.isEmpty, "the in-app warning follows the current state")
        let upAgain = evaluate(spent: 85_000, handled: handled)
        #expect(upAgain.event == nil, "not raised a second time")
        handled.formUnion(upAgain.markHandled)
        #expect(handled == [.eighty])
    }

    @Test func refundsBringingSpendNegativeReachNothing() {
        #expect(evaluate(spent: -5_000).reached.isEmpty)
        #expect(evaluate(spent: 0).reached.isEmpty)
    }

    @Test func raisedBudgetDoesNotRearm() {
        // 100% handled at ¥100,000; budget raised to ¥200,000 (now 55%); then spend reaches 85%.
        let raised = evaluate(budget: .yen(200_000), spent: 110_000, handled: [.eighty, .hundred])
        #expect(raised.reached.isEmpty && raised.event == nil)
        #expect(evaluate(budget: .yen(200_000), spent: 170_000, handled: [.eighty, .hundred]).event == nil)
    }

    @Test func loweredBudgetRaisesTheHighestEligible() {
        // ¥60,000 spent of ¥100,000; budget lowered to ¥50,000 → over 100%.
        let d = evaluate(budget: .yen(50_000), spent: 60_000)
        #expect(d.event?.threshold == .hundred)
        #expect(d.markHandled == [.eighty, .hundred])
        // Lowered only into the 80% band.
        #expect(evaluate(budget: .yen(70_000), spent: 60_000).event?.threshold == .eighty)
        // 80% already handled and lowered over 100%: 100% raised once.
        #expect(evaluate(budget: .yen(50_000), spent: 60_000, handled: [.eighty]).event?.threshold == .hundred)
    }

    @Test func newBudgetOverExistingSpendRaisesOnce() {
        // No budget while spending; then a budget is created below what was already spent.
        #expect(evaluate(budget: .unset, spent: 90_000) == .none)
        let created = evaluate(budget: .yen(100_000), spent: 90_000)
        #expect(created.event?.threshold == .eighty)
        #expect(evaluate(budget: .yen(100_000), spent: 90_000, handled: created.markHandled).event == nil)
    }

    @Test func removeAndReAddKeepsHistory() {
        // 80% handled, budget removed (nothing raised, history kept), then the same budget re-added.
        let handled: Set<BudgetThreshold> = [.eighty]
        let removed = evaluate(budget: .unset, spent: 85_000, handled: handled)
        #expect(removed.event == nil && removed.markHandled.isEmpty && removed.reached.isEmpty)
        let reAdded = evaluate(budget: .yen(100_000), spent: 85_000, handled: handled)
        #expect(reAdded.event == nil, "re-adding does not reset alerts")
        #expect(reAdded.reached == [.eighty], "but the warning shows again")
    }

    @Test func invalidOrUnusableBudgetsRaiseNothing() {
        #expect(evaluate(budget: .invalid(.notPositive), spent: 90_000) == .none)
        #expect(evaluate(budget: .yen(100_000), spent: nil) == .none)
    }

    // MARK: Months

    @Test func monthResetStartsFresh() {
        // November fully handled; December starts with nothing handled.
        let dec = LedgerMonth(year: 2026, month: 12)
        let d = evaluate(spent: 85_000, handled: [], month: dec, now: tokyo("2026-12-20"))
        #expect(d.event?.threshold == .eighty)
        // November's own state is not consulted for December, and vice versa.
        #expect(evaluate(spent: 120_000, handled: [.eighty, .hundred]).event == nil)
    }

    @Test func pastMonthsNeverRaise() {
        // Opening November in December, with November over budget and nothing handled.
        let d = evaluate(spent: 150_000, handled: [], now: tokyo("2026-12-03"))
        #expect(d.reached == [.eighty, .hundred], "the comparison still shows")
        #expect(d.event == nil)
        #expect(d.markHandled.isEmpty, "no catch-up for an old month")
    }

    @Test func tokyoDecidesTheMonth() {
        // 2026-11-30 15:30 UTC is 1 December 00:30 in Tokyo: November is already past.
        let instant = Date(timeIntervalSince1970: 1_796_052_600)
        #expect(evaluate(spent: 90_000, now: instant).event == nil)
        #expect(BudgetAlertPolicy.isStale(intentMonthKey: "2026-11", now: instant))
        #expect(!BudgetAlertPolicy.isStale(intentMonthKey: "2026-12", now: instant))
    }

    // MARK: Delivery

    @Test func notificationsOffStillConsumeTheEvent() {
        let off = evaluate(spent: 85_000, allowed: false)
        #expect(off.event == BudgetAlertEvent(threshold: .eighty, sendNotification: false), "in-app banner only")
        #expect(off.markHandled == [.eighty], "consumed, not queued")
        // Turning notifications on later does not replay it.
        #expect(evaluate(spent: 85_000, handled: off.markHandled, allowed: true).event == nil)
        // The in-app warning stays.
        #expect(evaluate(spent: 85_000, handled: off.markHandled, allowed: true).reached == [.eighty])
    }

    @Test func pendingNotificationsThatNoLongerApplyAreCancelled() {
        // 100% pending, then an expense is deleted before it is shown.
        let d = evaluate(spent: 90_000, handled: [.eighty, .hundred], pending: [.hundred])
        #expect(d.cancelPending == [.hundred])
        #expect(d.markHandled.isEmpty, "cancelling does not rearm")
        // Still applies: keep it.
        #expect(evaluate(spent: 120_000, handled: [.eighty, .hundred], pending: [.hundred]).cancelPending.isEmpty)
        // Budget removed: nothing pending applies.
        #expect(evaluate(budget: .unset, spent: 120_000, handled: [.eighty, .hundred], pending: [.eighty, .hundred])
            .cancelPending == [.eighty, .hundred])
    }

    // MARK: Overflow

    @Test func hugeValuesCompareExactly() {
        #expect(evaluate(budget: .yen(MonthlyBudget.maximumYen), spent: Int.max).reached == [.eighty, .hundred])
        #expect(evaluate(budget: .yen(MonthlyBudget.maximumYen), spent: MonthlyBudget.maximumYen - 1).reached == [.eighty])
        // 5·S overflows: still exact.
        #expect(BudgetAlertPolicy.atLeast(Int.max, numerator: 4, denominator: 5, of: 1_000))
        // Both sides overflow (not reachable with valid budgets): compared by quotient and remainder.
        let big = Int.max / 3
        #expect(BudgetAlertPolicy.atLeast(big, numerator: 4, denominator: 5, of: big))
        #expect(!BudgetAlertPolicy.atLeast(big / 2, numerator: 4, denominator: 5, of: big))
        let b = Int.max / 2          // 4·b overflows
        let threshold = b / 5 * 4 + (b % 5) * 4 / 5
        #expect(BudgetAlertPolicy.atLeast(threshold + 1, numerator: 4, denominator: 5, of: b))
        #expect(!BudgetAlertPolicy.atLeast(threshold - 1, numerator: 4, denominator: 5, of: b))
    }
}
