import Foundation
import KakeiboCore
import Observation

/// The "Set or edit budget" sheet for the current month (v1.1, B-04).
///
/// The view binds to `amountText` and `useForFutureMonths`. Validation, what Save does and
/// what a failure means live here, so they are tested with `swift test`. A failed save or
/// remove leaves the store unchanged (the repository rolls back) and sets `failure`, so the
/// sheet stays open and the ledger does not show a value that was never stored.
@MainActor
@Observable
public final class BudgetForm {
    public enum Failure: Equatable, Sendable {
        case save
        case remove
    }

    public let month: LedgerMonth
    /// What the user typed. Full-width digits, commas and ¥/円 are accepted (`MonthlyBudget.parse`).
    public var amountText: String
    /// "Use this amount for future months". Off unless the template is already on.
    public var useForFutureMonths: Bool
    /// True when the month already had a budget: the sheet offers Remove.
    public let hasBudget: Bool
    /// Set when the last save or remove failed; cleared by the next attempt.
    public private(set) var failure: Failure?

    private let repository: BudgetRepository
    private let originalAmount: String
    private let originalTemplateOn: Bool

    /// Opens the form for `month`, which must be the current Tokyo month (past months are read-only).
    public init(repository: BudgetRepository, month: LedgerMonth, now: Date) throws {
        self.repository = repository
        self.month = month
        let budget = try repository.budget(for: month, now: now)
        let amount = budget.yen.map(String.init) ?? ""
        let templateOn = try repository.template() != nil
        hasBudget = budget.yen != nil
        amountText = amount
        useForFutureMonths = templateOn
        originalAmount = amount
        originalTemplateOn = templateOn
    }

    /// The amount as read from `amountText`.
    public var parsed: MonthlyBudget { MonthlyBudget.parse(amountText) }

    /// Why Save is not allowed, or nil. `.unset` means nothing typed yet.
    public var problem: MonthlyBudget? {
        switch parsed {
        case .yen: nil
        case let other: other
        }
    }

    public var canSave: Bool { parsed.yen != nil }

    /// True when Cancel would lose something.
    public var hasUnsavedChanges: Bool {
        amountText != originalAmount || useForFutureMonths != originalTemplateOn
    }

    /// Saves. Returns true on success; on failure sets `failure` and stores nothing.
    @discardableResult
    public func save(now: Date = .now) -> Bool {
        failure = nil
        guard let yen = parsed.yen else { return false }
        do {
            try repository.saveBudget(yen, for: month, useForFutureMonths: useForFutureMonths, now: now)
            return true
        } catch {
            failure = .save
            return false
        }
    }

    /// Removes the month's budget (receipts and alert history stay). Returns true on success.
    @discardableResult
    public func remove(now: Date = .now) -> Bool {
        failure = nil
        do {
            try repository.removeBudget(for: month, now: now)
            return true
        } catch {
            failure = .remove
            return false
        }
    }
}
