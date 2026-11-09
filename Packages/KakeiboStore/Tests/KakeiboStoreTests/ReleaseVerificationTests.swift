import Foundation
import KakeiboCore
import SwiftData
import Testing
@testable import KakeiboStore

/// B-09: a v1.0 user's store, upgraded and used through a month and a year rollover, with the
/// app closed and reopened in between. Each step uses the store file on disk, as the app does.
@MainActor
@Suite struct ReleaseVerificationTests {
    final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    static func tokyo(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        Calendar.kakeibo.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static let november = LedgerMonth(year: 2026, month: 11)
    static let december = LedgerMonth(year: 2026, month: 12)
    static let january = LedgerMonth(year: 2027, month: 1)

    /// The app's services on one store file: what a launch creates.
    @MainActor
    final class Launch {
        let container: ModelContainer
        let expenses: ExpenseRepository
        let budgets: BudgetRepository
        let coordinator: BudgetAlertCoordinator
        let center: InMemoryNotificationCenter
        let notifier: BudgetNotifier

        init(url: URL, photos: PhotoStore, center: InMemoryNotificationCenter, settings: AppSettings, clock: Clock) throws {
            container = try KakeiboStore.makeContainer(url: url)
            expenses = ExpenseRepository(container: container, photoStore: photos)
            budgets = BudgetRepository(context: expenses.context)
            self.center = center
            notifier = BudgetNotifier(center: center, settings: settings) { _ in .init(title: "t", body: "b") }
            coordinator = BudgetAlertCoordinator(expenses: expenses, budgets: budgets, notifier: notifier,
                                                 now: { clock.now })
        }

        /// Launch or foreground: reconcile, then let every run finish.
        func reconcile() async {
            coordinator.reconcile()
            await settle()
        }

        func settle() async {
            for _ in 0..<2 {
                for _ in 0..<5 { await Task.yield() }
                await coordinator.waitUntilIdle()
            }
        }

        func spent(_ month: LedgerMonth) throws -> Int? {
            MonthSpend.total(try expenses.expenses(inMonth: month.key))
        }

        @discardableResult
        func spend(_ yen: Int, on day: String, now: Date) async throws -> Expense {
            let expense = try expenses.create(from: ReceiptDraft(storeName: "店", dayKey: day, totalYen: yen),
                                              source: .manual, now: now)
            await settle()
            return expense
        }
    }

    @Test func v1_0UserThroughUpgradeRestartAndRollovers() async throws {
        // A v1.0 store (schema V2) with three November expenses, one with a photo.
        let fixture = try #require(Bundle.module.url(forResource: "Fixtures/v2-store", withExtension: nil))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ReleaseVerification-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: fixture, to: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Kakeibo.store")
        let photos = try PhotoStore(directory: folder.appendingPathComponent("Receipts"))
        let photoName = "4C0E7B1A-0B2D-4D5E-8F10-1A2B3C4D5E01.jpg"
        try Data([0xFF, 0xD8, 0xFF]).write(to: photos.url(for: photoName))
        let suite = "ReleaseVerification-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let clock = Clock(Self.tokyo(2026, 11, 20))
        // iOS has never asked: v1.0 had no notifications.
        let center = InMemoryNotificationCenter(status: .notDetermined, answer: .allowed)

        // 1. First launch of v1.1: data kept, no budget, alerts off, nothing asked or sent.
        var app: Launch? = try Launch(url: url, photos: photos, center: center, settings: settings, clock: clock)
        await app!.reconcile()
        #expect(try app!.expenses.expenses(inMonth: Self.november.key).count == 3)
        #expect(try app!.spent(Self.november) == 3_606)
        #expect(try app!.budgets.budget(for: Self.november, now: clock.now) == .unset)
        #expect(!settings.budgetAlertsEnabled)
        #expect(await center.added.isEmpty)
        #expect(await center.requestCount == 0, "no permission prompt on upgrade or launch")
        #expect(app!.coordinator.banner == nil)

        // Photos and CSV export are as in v1.0.
        #expect(try app!.expenses.removeOrphanPhotos() == 0)
        #expect(FileManager.default.fileExists(atPath: try photos.url(for: photoName).path))
        let export = ExpenseExport(repository: app!.expenses, directory: folder.appendingPathComponent("Export"))
        let file = try export.prepare(month: Self.november)
        #expect(file.count == 3)
        #expect(file.totalYen == 3_606)
        let bytes = try Data(contentsOf: file.url)
        #expect(bytes.prefix(3) == Data([0xEF, 0xBB, 0xBF]))   // UTF-8 BOM, for Excel
        let csv = try #require(String(data: bytes, encoding: .utf8))
        #expect(csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count == 4)   // header + 3 rows
        #expect(csv.contains("ローソン"))

        // 2. The user turns alerts on in Settings (the only place iOS asks) and sets ¥4,000
        //    from this month on: 90% → the 80% alert.
        await app!.notifier.setEnabled(true)
        #expect(await center.requestCount == 1)
        #expect(settings.budgetAlertsEnabled)
        try app!.budgets.saveBudget(4_000, for: Self.november, useForFutureMonths: true, now: clock.now)
        await app!.settle()
        #expect(try app!.budgets.handledThresholds(for: Self.november) == [.eighty])
        #expect(await center.added == ["budget-2026-11-80"])
        #expect(app!.coordinator.banner?.threshold == .eighty)

        // 3. The app is closed and opened again: nothing is replayed.
        app = nil
        app = try Launch(url: url, photos: photos, center: center, settings: settings, clock: clock)
        await app!.reconcile()
        #expect(try app!.budgets.budget(for: Self.november, now: clock.now) == .yen(4_000))
        #expect(try app!.budgets.handledThresholds(for: Self.november) == [.eighty])
        #expect(await center.added == ["budget-2026-11-80"])
        #expect(app!.coordinator.banner == nil)
        #expect(await center.requestCount == 1, "not asked again after a restart")

        // 4. Midnight into December: the template gives ¥4,000, the month starts fresh.
        clock.now = Self.tokyo(2026, 12, 1, hour: 0)
        await app!.reconcile()
        #expect(try app!.budgets.budget(for: Self.december, now: clock.now) == .yen(4_000))
        #expect(try app!.spent(Self.december) == 0)
        #expect(try app!.budgets.handledThresholds(for: Self.december).isEmpty)
        // November is closed: more spend there (a late receipt) raises nothing.
        try await app!.spend(1_000, on: "2026-11-30", now: clock.now)
        #expect(await center.added == ["budget-2026-11-80"])
        // December: ¥3,300 is 82%.
        let lateID = try await app!.spend(3_300, on: "2026-12-31", now: clock.now).id
        #expect(await center.added == ["budget-2026-11-80", "budget-2026-12-80"])

        // 5. Midnight into the new year, after a restart.
        app = nil
        clock.now = Self.tokyo(2027, 1, 1, hour: 0)
        app = try Launch(url: url, photos: photos, center: center, settings: settings, clock: clock)
        await app!.reconcile()
        #expect(try app!.budgets.budget(for: Self.january, now: clock.now) == .yen(4_000))
        #expect(try app!.spent(Self.january) == 0)
        #expect(try app!.spent(Self.december) == 3_300)

        // 6. Moving the 31 December expense to 2 January moves its spend: January reaches 80%,
        //    December's alert is not raised again.
        let moved = try #require(try app!.expenses.expense(id: lateID))
        try app!.expenses.update(moved, now: clock.now) { $0.dayKey = "2027-01-02" }
        await app!.settle()
        #expect(try app!.spent(Self.december) == 0)
        #expect(try app!.spent(Self.january) == 3_300)
        #expect(try app!.budgets.handledThresholds(for: Self.december) == [.eighty])
        #expect(try app!.budgets.handledThresholds(for: Self.january) == [.eighty])
        #expect(await center.added == ["budget-2026-11-80", "budget-2026-12-80", "budget-2027-01-80"])

        // Then a jump straight past 100% raises only 100%.
        try await app!.spend(2_000, on: "2027-01-03", now: clock.now)
        #expect(try app!.budgets.handledThresholds(for: Self.january) == [.eighty, .hundred])
        #expect(await center.added.last == "budget-2027-01-100")

        // The v1.0 expenses are still there, untouched.
        #expect(try app!.expenses.expenses(inMonth: Self.november.key).count == 4)
        #expect(try app!.expenses.expense(id: UUID(uuidString: "4C0E7B1A-0B2D-4D5E-8F10-1A2B3C4D5E01")!)?.photoFileName == photoName)
    }
}
