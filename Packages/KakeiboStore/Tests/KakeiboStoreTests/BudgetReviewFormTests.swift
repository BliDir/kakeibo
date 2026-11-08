import Foundation
import KakeiboCore
import SwiftData
import Testing
@testable import KakeiboStore

/// The budget review sheet's logic (v1.2, BI-05): `LedgerModel.makeBudgetReview()` and `BudgetReviewForm`.
@MainActor
@Suite struct BudgetReviewFormTests {
    let container: ModelContainer
    let repo: ExpenseRepository
    let budgets: BudgetRepository
    static let today = Date(timeIntervalSince1970: 1_795_143_600) // Friday 2026-11-20 12:00 Tokyo
    static let november = LedgerMonth(year: 2026, month: 11)

    init() throws {
        container = try KakeiboStore.makeContainer(inMemory: true)
        repo = ExpenseRepository(container: container)
        budgets = BudgetRepository(context: repo.context)
    }

    private func model() -> LedgerModel {
        LedgerModel(repository: repo, budgets: budgets, today: { Self.today })
    }

    private var storeNumber = 0

    /// Each expense at its own store, so drivers are about categories.
    private mutating func add(_ day: String, _ total: Int, _ category: ExpenseCategory = .groceries) throws {
        storeNumber += 1
        _ = try repo.create(from: ReceiptDraft(storeName: "店\(storeNumber)", dayKey: day, totalYen: total, category: category),
                            source: .manual, now: Self.today)
    }

    /// ¥30,000 of groceries and four ¥1,000 meals out: ¥34,000.
    private mutating func usual(_ month: String) throws {
        try add("\(month)-10", 30_000)
        for d in ["05", "12", "19", "26"] { try add("\(month)-\(d)", 1_000, .dining) }
    }

    /// Groceries as usual and eight ¥2,000 meals out: ¥46,000.
    private mutating func diningHeavy(_ month: String) throws {
        try add("\(month)-10", 30_000)
        for d in 1...8 { try add("\(month)-\(String(format: "%02d", d * 3))", 2_000, .dining) }
    }

    private func setPastBudget(_ yen: Int, _ monthKey: String) throws {
        repo.context.insert(BudgetMonth(monthKey: monthKey, budgetYen: yen, createdAt: Self.today, updatedAt: Self.today))
        try repo.context.save()
    }

    /// Over budget with dining out up in September, October and November: raise to ¥46,000.
    private mutating func raiseFixture() throws {
        for month in ["2026-06", "2026-07", "2026-08"] { try usual(month) }
        try diningHeavy("2026-09")
        try diningHeavy("2026-10")
        try add("2026-11-10", 30_000)
        for d in [2, 5, 8, 11, 14, 17] { try add("2026-11-\(String(format: "%02d", d))", 2_000, .dining) } // ¥42,000
        try budgets.setBudget(30_000, for: Self.november, now: Self.today)
    }

    /// On pace (90%) after three months well under a ¥60,000 budget: lower to ¥34,000.
    private mutating func lowerFixture(pastBudgets: Bool = true) throws {
        for month in ["2026-08", "2026-09", "2026-10"] {
            try usual(month)
            if pastBudgets { try setPastBudget(60_000, month) }
        }
        try add("2026-11-03", 30_000)
        try add("2026-11-10", 10_000)
        try add("2026-11-15", 10_000)
        for d in [4, 8, 12, 16] { try add("2026-11-\(String(format: "%02d", d))", 1_000, .dining) } // ¥54,000
        try budgets.setBudget(60_000, for: Self.november, now: Self.today)
    }

    // MARK: Recommendations

    @Test mutating func raiseStartsOnThisMonthWithTheSuggestedAmount() throws {
        try raiseFixture()
        let form = try #require(model().makeBudgetReview())

        #expect(form.review.recommendation == .raise(toYen: 46_000, category: .dining))
        #expect(form.review.currentBudget == .yen(30_000))
        #expect(form.hasSuggestion)
        #expect(form.choice == .thisMonthOnly)
        #expect(form.amountText == "46000")
        #expect(form.isAmountEditable)
        #expect(!form.isReadOnly)
        #expect(!form.hasUnsavedChanges)
    }

    @Test mutating func previewUsesB01Figures() throws {
        try raiseFixture()
        let form = try #require(model().makeBudgetReview())

        // ¥46,000 − ¥42,000 = ¥4,000 left; 11 days with today; 3 days to Sunday.
        let change = try #require(form.preview)
        #expect(change.remainingYen == 4_000)
        #expect(change.dailyAmountYen == 363)
        #expect(change.weeklyAmountYen == 1_090)
        #expect(!change.appliesToFutureMonths)

        form.choice = .fromThisMonthOn
        #expect(form.preview?.appliesToFutureMonths == true)

        // Keep: still ¥12,000 over, nothing for the rest of the month.
        form.choice = .keep
        let keep = try #require(form.preview)
        #expect(keep.remainingYen == -12_000)
        #expect(keep.dailyAmountYen == 0)
        #expect(keep.weeklyAmountYen == 0)
        #expect(!form.isAmountEditable)
    }

    @Test mutating func lowerAfterThreeMonthsWellUnder() throws {
        try lowerFixture()
        let form = try #require(model().makeBudgetReview())
        #expect(form.review.recommendation == .lower(toYen: 34_000))
        #expect(form.choice == .thisMonthOnly)
        #expect(form.amountText == "34000")
    }

    @Test mutating func keepWhenNothingCallsForAChange() throws {
        try lowerFixture(pastBudgets: false)
        let form = try #require(model().makeBudgetReview())
        #expect(form.review.recommendation == .keep(.noChangeNeeded))
        #expect(form.choice == .keep)
        // Prefilled with the suggested amount for when the user picks a change.
        #expect(form.amountText == "34000")
        #expect(!form.isAmountEditable)
        #expect(form.canConfirm)
    }

    @Test mutating func keepWhenAOneOffExplainsTheOverspend() throws {
        for month in ["2026-08", "2026-09", "2026-10"] { try usual(month) }
        try add("2026-11-10", 30_000)
        try repo.create(from: ReceiptDraft(storeName: "ニトリ", dayKey: "2026-11-14", totalYen: 20_000, category: .household),
                        source: .manual, now: Self.today)
        try budgets.setBudget(40_000, for: Self.november, now: Self.today)
        let form = try #require(model().makeBudgetReview())
        #expect(form.review.recommendation == .keep(.oneOffOverspend))
        #expect(form.choice == .keep)
    }

    @Test mutating func notEnoughHistoryOffersAManualEditOfTheCurrentBudget() throws {
        try usual("2026-10")
        try add("2026-11-03", 45_000)
        try budgets.setBudget(40_000, for: Self.november, now: Self.today)
        let form = try #require(model().makeBudgetReview())

        #expect(form.review.suggested == .notEnoughHistory)
        #expect(!form.hasSuggestion)
        #expect(form.choice == .keep)
        #expect(form.amountText == "40000")
        form.choice = .thisMonthOnly
        form.amountText = "50000"
        #expect(form.preview?.remainingYen == 5_000)
        #expect(form.confirm())
        #expect(try budgets.budget(for: Self.november, now: Self.today) == .yen(50_000))
    }

    @Test func noReviewWithoutABudget() throws {
        #expect(model().makeBudgetReview() == nil)
    }

    // MARK: Closed months

    @Test mutating func closedMonthIsReadOnly() throws {
        for month in ["2026-07", "2026-08", "2026-09"] { try usual(month) }
        try diningHeavy("2026-10")
        try setPastBudget(30_000, "2026-10")
        let ledger = model()
        ledger.showPrevious()
        let form = try #require(ledger.makeBudgetReview())

        #expect(form.month.key == "2026-10")
        #expect(form.isReadOnly)
        #expect(form.choice == .keep)
        #expect(!form.isAmountEditable)
        #expect(form.preview == nil)
        #expect(!form.canConfirm)
        form.choice = .thisMonthOnly
        #expect(!form.confirm())
        #expect(try budgets.row(for: LedgerMonth(year: 2026, month: 10))?.budgetYen == 30_000)
    }

    // MARK: Input

    @Test mutating func invalidAmountsBlockConfirm() throws {
        try raiseFixture()
        let form = try #require(model().makeBudgetReview())
        for (text, problem) in [("0", MonthlyBudget.Problem.notPositive), ("12.5", .notWholeYen),
                                ("1000000000", .tooLarge), ("-100", .notPositive)] {
            form.amountText = text
            #expect(form.problem == problem, "\(text)")
            #expect(!form.canConfirm, "\(text)")
            #expect(form.preview == nil, "\(text)")
            #expect(!form.confirm(), "\(text)")
        }
        form.amountText = ""
        #expect(form.problem == nil)
        #expect(!form.canConfirm)
        form.amountText = "５０,０００円"
        #expect(form.canConfirm)
        #expect(form.hasUnsavedChanges)
        // Keep ignores the field.
        form.amountText = "0"
        form.choice = .keep
        #expect(form.problem == nil)
        #expect(form.canConfirm)
        #expect(try budgets.budget(for: Self.november, now: Self.today) == .yen(30_000))
    }

    // MARK: Saving

    @Test mutating func thisMonthOnlyLeavesFutureMonthsAlone() throws {
        try raiseFixture()
        try budgets.setTemplate(amountYen: 35_000, now: Self.today)
        let form = try #require(model().makeBudgetReview())
        form.choice = .thisMonthOnly
        #expect(form.confirm())
        #expect(try budgets.budget(for: Self.november, now: Self.today) == .yen(46_000))
        #expect(try budgets.template()?.amountYen == 35_000)
    }

    @Test mutating func fromThisMonthOnSavesTheTemplateFromNextMonth() throws {
        try raiseFixture()
        let form = try #require(model().makeBudgetReview())
        form.choice = .fromThisMonthOn
        form.amountText = "45000"
        #expect(form.confirm())
        #expect(try budgets.budget(for: Self.november, now: Self.today) == .yen(45_000))
        let template = try #require(try budgets.template())
        #expect(template.amountYen == 45_000)
        #expect(template.startMonthKey == "2026-12")
    }

    @Test mutating func keepStoresNothing() throws {
        try raiseFixture()
        try budgets.setTemplate(amountYen: 35_000, now: Self.today)
        let form = try #require(model().makeBudgetReview())
        form.choice = .keep
        var saves = 0
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: repo.context,
                                                              queue: nil) { _ in saves += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        #expect(form.confirm())
        #expect(saves == 0)
        #expect(try budgets.budget(for: Self.november, now: Self.today) == .yen(30_000))
        #expect(try budgets.template()?.amountYen == 35_000)
    }

    @Test mutating func failedSaveKeepsTheInputAndRetries() throws {
        try raiseFixture()
        let form = try #require(model().makeBudgetReview())
        form.amountText = "47000"
        var fail = true
        budgets.beforeSave = { if fail { throw CocoaError(.fileWriteUnknown) } }

        #expect(!form.confirm())
        #expect(form.saveFailed)
        #expect(form.amountText == "47000")
        #expect(form.choice == .thisMonthOnly)
        #expect(try budgets.budget(for: Self.november, now: Self.today) == .yen(30_000))

        fail = false
        #expect(form.confirm())
        #expect(!form.saveFailed)
        #expect(try budgets.budget(for: Self.november, now: Self.today) == .yen(47_000))
    }

    @Test mutating func savingRefreshesProgressAndInsight() throws {
        try raiseFixture()
        let ledger = model()
        #expect(ledger.overspend?.insight.state == .overBudget)
        let form = try #require(ledger.makeBudgetReview())
        form.amountText = "100000"
        #expect(form.confirm())
        #expect(ledger.budgetSummary?.budgetYen == 100_000)
        #expect(ledger.overspend == nil)
    }

    // MARK: Repository

    @Test func storedBudgetsBetweenMonths() throws {
        try setPastBudget(10_000, "2026-08")
        try setPastBudget(20_000, "2026-10")
        try budgets.setBudget(30_000, for: Self.november, now: Self.today)
        let found = try budgets.budgets(from: LedgerMonth(year: 2026, month: 9), before: Self.november)
        #expect(found == [LedgerMonth(year: 2026, month: 10): .yen(20_000)])
    }
}
