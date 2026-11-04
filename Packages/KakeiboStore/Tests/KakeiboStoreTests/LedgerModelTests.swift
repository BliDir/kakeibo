import Foundation
import KakeiboCore
import SwiftData
import Testing
@testable import KakeiboStore

@MainActor
@Suite struct LedgerModelTests {
    let repo: ExpenseRepository
    static let today = Date(timeIntervalSince1970: 1_793_674_800) // 2026-11-03 12:00 Tokyo

    init() throws {
        repo = ExpenseRepository(container: try KakeiboStore.makeContainer(inMemory: true))
    }

    @discardableResult
    private func add(_ day: String, _ total: Int, _ category: ExpenseCategory = .groceries, tax8: Int? = nil) throws -> Expense {
        try repo.create(from: ReceiptDraft(dayKey: day, totalYen: total, tax8Yen: tax8, category: category),
                        source: .manual, now: Self.today)
    }

    @Test func opensOnTheCurrentMonth() {
        let model = LedgerModel(repository: repo, today: { Self.today })
        #expect(model.month == LedgerMonth(year: 2026, month: 11))
        #expect(model.isEmpty)
        #expect(model.summary == .empty)
        #expect(!model.canShowNext)
    }

    @Test func showsTheMonthGroupedByDay() throws {
        try add("2026-11-03", 1_310, tax8: 72)
        try add("2026-11-03", 660, .household)
        try add("2026-11-01", 2_150, .transport)
        try add("2026-10-31", 999)
        let model = LedgerModel(repository: repo, today: { Self.today })

        #expect(model.summary.totalYen == 4_120)
        #expect(model.summary.count == 3)
        #expect(model.summary.taxYen == 72)
        #expect(model.days.map(\.dayKey) == ["2026-11-03", "2026-11-01"])
        #expect(model.days.map(\.subtotalYen) == [1_970, 2_150])
    }

    @Test func monthNavigationStopsAtTheCurrentMonth() throws {
        try add("2026-10-31", 999)
        let model = LedgerModel(repository: repo, today: { Self.today })
        model.showNext()
        #expect(model.month == LedgerMonth(year: 2026, month: 11))

        model.showPrevious()
        #expect(model.month == LedgerMonth(year: 2026, month: 10))
        #expect(model.summary.totalYen == 999)
        #expect(model.canShowNext)

        model.showNext()
        #expect(model.month == LedgerMonth(year: 2026, month: 11))
        model.show(LedgerMonth(year: 2027, month: 3))
        #expect(model.month == LedgerMonth(year: 2026, month: 11))
    }

    @Test func updatesLiveAfterSaveAndDelete() async throws {
        let model = LedgerModel(repository: repo, today: { Self.today })
        let expense = try add("2026-11-02", 500)
        await Task.yield()
        #expect(model.summary.totalYen == 500)

        try repo.update(expense) { $0.totalYen = 800 }
        await Task.yield()
        #expect(model.summary.totalYen == 800)

        try repo.delete(expense)
        await Task.yield()
        #expect(model.isEmpty)
    }
}
