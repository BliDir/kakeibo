import Foundation
import KakeiboCore
import SwiftData

/// Where a budget alert notification stands. Raw values are stored on disk; never rename.
public enum BudgetAlertIntentState: String, CaseIterable, Sendable {
    /// Decided and handed to the system (or about to be); not known to be shown yet.
    case pending
    /// Handed to iOS, which accepted it. Budget alerts have no trigger, so iOS shows them at
    /// once unless it holds them back (Focus, permission); this is not proof the user saw it.
    case delivered
    /// No longer applies (spend or budget changed first), or alerts were off. Never re-sent.
    case cancelled
}

/// Reads and writes monthly budgets, the future-month template and budget alert state.
///
/// Rules (Kakeibo iOS v1.1 release plan, proposed defaults):
/// - One budget per Tokyo month. Only the current month can be set, changed or removed;
///   past months are read-only (`Error.readOnlyMonth`).
/// - Removing a budget keeps the month's row, so receipts are untouched, alert history
///   survives a re-add, and the template is not applied to that month later.
/// - The template is off unless the user turns it on. It applies only to months that start
///   after it was saved, and only the first time such a month is read while it is the current
///   month. It never changes a month that already has a row.
///
/// Runs on the main actor with the same context as `ExpenseRepository`, so writes are
/// serialized. Every write saves, or rolls back and throws, leaving nothing half-done.
@MainActor
public final class BudgetRepository {
    public enum Error: Swift.Error, Equatable {
        /// Only the current month's budget can be changed.
        case readOnlyMonth(String)
        /// The amount cannot be a budget.
        case invalidBudget(MonthlyBudget.Problem)
    }

    public let context: ModelContext
    /// Held so the container outlives its context.
    private let container: ModelContainer?
    /// Tests (and Debug `KAKEIBO_FAIL_BUDGET_SAVES`): runs right before each save; throwing
    /// simulates a failed save.
    public var beforeSave: (() throws -> Void)?

    public init(context: ModelContext) {
        self.context = context
        container = nil
    }

    public init(container: ModelContainer) {
        context = container.mainContext
        self.container = container
    }

    // MARK: - Reading

    /// The month's budget. For the current month with no row yet, applies the template if it is
    /// on and due (and saves that). Past and future months are only read, never set up.
    public func budget(for month: LedgerMonth, now: Date) throws -> MonthlyBudget {
        if let row = try row(for: month) { return row.budget }
        guard month == LedgerMonth(containing: now), let template = try template(),
              month.key >= template.startMonthKey else { return .unset }
        let row = BudgetMonth(monthKey: month.key, budgetYen: template.amountYen, appliedFromTemplate: true,
                              createdAt: now, updatedAt: now)
        try commit { context.insert(row) }
        return row.budget
    }

    /// The month's row, if it has one. No side effects.
    public func row(for month: LedgerMonth) throws -> BudgetMonth? {
        let key = month.key
        var descriptor = FetchDescriptor<BudgetMonth>(predicate: #Predicate { $0.monthKey == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Stored budgets of the months from `first` up to (not including) `end`, for the budget
    /// review (BI-03's `pastBudgets`). Months without a row are left out. No side effects.
    public func budgets(from first: LedgerMonth, before end: LedgerMonth) throws -> [LedgerMonth: MonthlyBudget] {
        let low = first.key, high = end.key
        let rows = try context.fetch(FetchDescriptor<BudgetMonth>(predicate: #Predicate {
            $0.monthKey >= low && $0.monthKey < high
        }))
        var result: [LedgerMonth: MonthlyBudget] = [:]
        for row in rows {
            guard let month = LedgerMonth(dayKey: row.monthKey + "-01") else { continue }
            result[month] = row.budget
        }
        return result
    }

    /// The future-month template, if on.
    public func template() throws -> BudgetTemplate? {
        let key = BudgetTemplate.singletonKey
        var descriptor = FetchDescriptor<BudgetTemplate>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Editing the current month

    /// Sets or changes the current month's budget.
    public func setBudget(_ yen: Int, for month: LedgerMonth, now: Date) throws {
        try requireCurrent(month, now: now)
        guard case .yen(let amount) = MonthlyBudget.validated(yen) else {
            if case .invalid(let problem) = MonthlyBudget.validated(yen) { throw Error.invalidBudget(problem) }
            throw Error.invalidBudget(.notPositive)
        }
        let existing = try row(for: month)
        try commit {
            let row = existing ?? {
                let new = BudgetMonth(monthKey: month.key, createdAt: now, updatedAt: now)
                context.insert(new)
                return new
            }()
            row.budgetYen = amount
            row.appliedFromTemplate = false
            row.updatedAt = now
        }
    }

    /// Sets the current month's budget and the "use this amount for future months" choice in
    /// one write: both are saved, or neither. On: the template becomes `yen` from next month.
    /// Off: any template is turned off (future months only; this month keeps `yen`).
    public func saveBudget(_ yen: Int, for month: LedgerMonth, useForFutureMonths: Bool, now: Date) throws {
        try requireCurrent(month, now: now)
        guard case .yen(let amount) = MonthlyBudget.validated(yen) else {
            if case .invalid(let problem) = MonthlyBudget.validated(yen) { throw Error.invalidBudget(problem) }
            throw Error.invalidBudget(.notPositive)
        }
        let existing = try row(for: month)
        let existingTemplate = try template()
        let start = month.next.key
        try commit {
            let row = existing ?? {
                let new = BudgetMonth(monthKey: month.key, createdAt: now, updatedAt: now)
                context.insert(new)
                return new
            }()
            row.budgetYen = amount
            row.appliedFromTemplate = false
            row.updatedAt = now
            switch (useForFutureMonths, existingTemplate) {
            case (true, let template?):
                template.amountYen = amount
                template.startMonthKey = start
                template.updatedAt = now
            case (true, nil):
                context.insert(BudgetTemplate(amountYen: amount, startMonthKey: start, createdAt: now, updatedAt: now))
            case (false, let template?):
                context.delete(template)
            case (false, nil):
                break
            }
        }
    }

    /// Removes the current month's budget. Its expenses are not touched, and its handled
    /// thresholds and alert intents stay, so removing and re-adding does not reset alerts.
    public func removeBudget(for month: LedgerMonth, now: Date) throws {
        try requireCurrent(month, now: now)
        let existing = try row(for: month)
        try commit {
            let row = existing ?? {
                // No row yet: record the removal, so the template is not applied to this month.
                let new = BudgetMonth(monthKey: month.key, createdAt: now, updatedAt: now)
                context.insert(new)
                return new
            }()
            row.budgetYen = nil
            row.appliedFromTemplate = false
            row.updatedAt = now
        }
    }

    // MARK: - Template

    /// Turns the future-month template on with `amountYen`, or off with nil.
    /// It applies from the month after `now`; existing months, the current one included, never change.
    public func setTemplate(amountYen: Int?, now: Date) throws {
        let existing = try template()
        guard let amountYen else {
            guard let existing else { return }
            try commit { context.delete(existing) }
            return
        }
        guard case .yen(let amount) = MonthlyBudget.validated(amountYen) else {
            if case .invalid(let problem) = MonthlyBudget.validated(amountYen) { throw Error.invalidBudget(problem) }
            throw Error.invalidBudget(.notPositive)
        }
        let start = LedgerMonth(containing: now).next.key
        try commit {
            if let existing {
                existing.amountYen = amount
                existing.startMonthKey = start
                existing.updatedAt = now
            } else {
                context.insert(BudgetTemplate(amountYen: amount, startMonthKey: start, createdAt: now, updatedAt: now))
            }
        }
    }

    // MARK: - Alert state

    /// Thresholds already handled in the month.
    public func handledThresholds(for month: LedgerMonth) throws -> Set<BudgetThreshold> {
        try row(for: month)?.handledThresholds ?? []
    }

    /// Marks thresholds handled for the month (creating its row if needed). Never un-marks:
    /// once handled, a threshold stays handled for that month, even if the budget is removed.
    public func markHandled(_ thresholds: Set<BudgetThreshold>, for month: LedgerMonth, now: Date) throws {
        guard !thresholds.isEmpty else { return }
        let existing = try row(for: month)
        try commit {
            let row = existing ?? {
                let new = BudgetMonth(monthKey: month.key, createdAt: now, updatedAt: now)
                context.insert(new)
                return new
            }()
            if thresholds.contains(.eighty) { row.handledEighty = true }
            if thresholds.contains(.hundred) { row.handledHundred = true }
            row.updatedAt = now
        }
    }

    /// The notification intent for a month and threshold, if one was recorded.
    public func intent(for month: LedgerMonth, threshold: BudgetThreshold) throws -> BudgetAlertIntent? {
        let id = BudgetAlertIntent.requestID(monthKey: month.key, threshold: threshold)
        var descriptor = FetchDescriptor<BudgetAlertIntent>(predicate: #Predicate { $0.requestID == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Records the intent to notify for a month and threshold, or updates its state.
    /// One row per month and threshold, keyed by its stable request ID.
    @discardableResult
    public func recordIntent(for month: LedgerMonth, threshold: BudgetThreshold,
                             state: BudgetAlertIntentState, now: Date) throws -> BudgetAlertIntent {
        let existing = try intent(for: month, threshold: threshold)
        var result: BudgetAlertIntent?
        try commit {
            if let existing {
                existing.state = state
                existing.updatedAt = now
                result = existing
            } else {
                let new = BudgetAlertIntent(monthKey: month.key, threshold: threshold, state: state,
                                            createdAt: now, updatedAt: now)
                context.insert(new)
                result = new
            }
        }
        return result!
    }

    /// One intent state change, for `storeAlertDecision`.
    public struct IntentChange: Sendable, Equatable {
        public var month: LedgerMonth
        public var threshold: BudgetThreshold
        public var state: BudgetAlertIntentState

        public init(_ month: LedgerMonth, _ threshold: BudgetThreshold, _ state: BudgetAlertIntentState) {
            self.month = month
            self.threshold = threshold
            self.state = state
        }
    }

    /// Stores one alert decision in a single save, all or nothing: thresholds now handled for
    /// `month` and intent state changes. A crash can then never leave a threshold handled
    /// without its intent (a lost alert) or the other way round. Later changes to the same
    /// intent win.
    public func storeAlertDecision(markHandled thresholds: Set<BudgetThreshold>, for month: LedgerMonth,
                                   intents changes: [IntentChange], now: Date) throws {
        var latest: [String: IntentChange] = [:]
        var order: [String] = []
        for change in changes {
            let id = BudgetAlertIntent.requestID(monthKey: change.month.key, threshold: change.threshold)
            if latest[id] == nil { order.append(id) }
            latest[id] = change
        }
        guard !thresholds.isEmpty || !order.isEmpty else { return }
        let existingRow = thresholds.isEmpty ? nil : try row(for: month)
        let existingIntents = try order.map { id -> BudgetAlertIntent? in
            let change = latest[id]!
            return try intent(for: change.month, threshold: change.threshold)
        }
        try commit {
            if !thresholds.isEmpty {
                let row = existingRow ?? {
                    let new = BudgetMonth(monthKey: month.key, createdAt: now, updatedAt: now)
                    context.insert(new)
                    return new
                }()
                if thresholds.contains(.eighty) { row.handledEighty = true }
                if thresholds.contains(.hundred) { row.handledHundred = true }
                row.updatedAt = now
            }
            for (id, existing) in zip(order, existingIntents) {
                let change = latest[id]!
                if let existing {
                    existing.state = change.state
                    existing.updatedAt = now
                } else {
                    context.insert(BudgetAlertIntent(monthKey: change.month.key, threshold: change.threshold,
                                                     state: change.state, createdAt: now, updatedAt: now))
                }
            }
        }
    }

    /// Intents in a state, oldest first (for reconciling notifications on launch).
    public func intents(in state: BudgetAlertIntentState) throws -> [BudgetAlertIntent] {
        let raw = state.rawValue
        let descriptor = FetchDescriptor<BudgetAlertIntent>(
            predicate: #Predicate { $0.stateRaw == raw },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Helpers

    private func requireCurrent(_ month: LedgerMonth, now: Date) throws {
        guard month == LedgerMonth(containing: now) else { throw Error.readOnlyMonth(month.key) }
    }

    /// Applies `change` and saves; on any failure rolls the context back and rethrows.
    private func commit(_ change: () -> Void) throws {
        change()
        do {
            try beforeSave?()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
