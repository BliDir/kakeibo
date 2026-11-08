import Foundation
import KakeiboCore
import Observation

/// The budget review sheet (v1.2, BI-05), opened from the analysis' "Review budget".
///
/// Shows BI-03's `BudgetReview` (current and suggested budget, the recommendation) and lets the
/// user keep the budget, change it for this month only, or change it from this month on. The
/// view binds to `choice` and `amountText`; previews, validation and saving live here, so they
/// are tested with `swift test`. Nothing is stored until `confirm()`.
///
/// Saving reuses the B-02/B-04 repository writes, so the ledger, insights and alerts refresh
/// through `ModelContext.didSave` like any other budget change:
/// - this month only: `BudgetRepository.setBudget` (the future-month template is left as it is);
/// - from this month on: `BudgetRepository.saveBudget(_:for:useForFutureMonths: true, now:)`,
///   B-04's "Use this amount for future months".
@MainActor
@Observable
public final class BudgetReviewForm {
    public let review: BudgetReview
    /// The chosen option. Starts on "this month only" when the review recommends a change,
    /// otherwise on keep: the recommendation is never applied without the user confirming.
    public var choice: BudgetReview.Choice
    /// The new amount for the change choices: the suggested budget, or the current one when
    /// there is not enough history for a suggestion. Ignored (and not editable) for keep.
    public var amountText: String
    /// Set when the last confirm failed to save; cleared by the next attempt. The input stays.
    public private(set) var saveFailed = false

    private let repository: BudgetRepository
    private let now: () -> Date
    private let originalChoice: BudgetReview.Choice
    private let originalAmount: String

    public init(review: BudgetReview, repository: BudgetRepository, now: @escaping () -> Date) {
        self.review = review
        self.repository = repository
        self.now = now
        let amount = (review.suggested.yen ?? review.currentBudget.yen).map(String.init) ?? ""
        let choice: BudgetReview.Choice = switch review.recommendation {
        case .raise, .lower: review.isEditable ? .thisMonthOnly : .keep
        case .keep: .keep
        }
        self.choice = choice
        amountText = amount
        originalChoice = choice
        originalAmount = amount
    }

    public var month: LedgerMonth { review.month }

    /// A closed month (or one that ended while the sheet was open) opens read only.
    public var isReadOnly: Bool { !review.isEditable || LedgerMonth(containing: now()) != review.month }

    /// Fewer than 2 baseline months: no suggested budget or recommendation, manual edit only.
    public var hasSuggestion: Bool { review.suggested.yen != nil }

    /// The amount field takes input only for the change choices.
    public var isAmountEditable: Bool { !isReadOnly && choice != .keep }

    /// The typed amount (full-width digits, commas and ¥/円 accepted, as in B-04).
    public var parsed: MonthlyBudget { MonthlyBudget.parse(amountText) }

    /// What is wrong with the typed amount, for the change choices; nil when it is fine or unused.
    public var problem: MonthlyBudget.Problem? {
        guard isAmountEditable, case .invalid(let problem) = parsed else { return nil }
        return problem
    }

    /// The chosen option's effect on this month (B-01 figures), or nil while the amount is not
    /// a valid budget or the month is read only.
    public var preview: BudgetPreview? {
        guard !isReadOnly else { return nil }
        switch choice {
        case .keep:
            return review.preview(.keep, now: now())
        case .thisMonthOnly, .fromThisMonthOn:
            guard let yen = parsed.yen else { return nil }
            return review.preview(choice, newBudgetYen: yen, now: now())
        }
    }

    public var canConfirm: Bool {
        guard !isReadOnly else { return false }
        return choice == .keep || parsed.yen != nil
    }

    /// True when closing the sheet would lose a choice the user made.
    public var hasUnsavedChanges: Bool { choice != originalChoice || amountText != originalAmount }

    /// Applies the choice. Keep stores nothing. Returns true when the sheet can close; on a
    /// failed save sets `saveFailed`, keeps the input and stores nothing (the repository rolls back).
    @discardableResult
    public func confirm() -> Bool {
        saveFailed = false
        guard canConfirm else { return false }
        let date = now()
        do {
            switch choice {
            case .keep:
                return true
            case .thisMonthOnly:
                guard let yen = parsed.yen else { return false }
                try repository.setBudget(yen, for: month, now: date)
            case .fromThisMonthOn:
                guard let yen = parsed.yen else { return false }
                try repository.saveBudget(yen, for: month, useForFutureMonths: true, now: date)
            }
            return true
        } catch {
            saveFailed = true
            return false
        }
    }
}
