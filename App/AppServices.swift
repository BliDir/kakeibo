import Foundation
import KakeiboCore
import KakeiboScan
import KakeiboStore
import SwiftData
import UserNotifications

/// The app's long-lived services, made once at launch.
@MainActor
final class AppServices {
    let container: ModelContainer
    let photoStore: PhotoStore?
    let repository: ExpenseRepository
    let budgets: BudgetRepository
    let pipeline: ExtractionPipeline
    let settings: AppSettings
    /// Budget alerts: the user's opt-in, the iOS permission, sending and cancelling.
    let notifier: BudgetNotifier
    /// Runs the 80%/100% alert policy after every committed change and on reconcile.
    let alerts: BudgetAlertCoordinator
    /// Where a tapped budget notification asks to go.
    let router = NotificationRouter()
    /// Kept alive here: the notification center holds its delegate weakly.
    private var notificationDelegate: BudgetNotificationDelegate?

    init(container: ModelContainer, photoStore: PhotoStore?, pipeline: ExtractionPipeline,
         settings: AppSettings = AppSettings(), notificationCenter: (any BudgetNotificationCenter)? = nil) {
        self.container = container
        self.photoStore = photoStore
        self.pipeline = pipeline
        self.settings = settings
        repository = ExpenseRepository(container: container, photoStore: photoStore)
        budgets = BudgetRepository(container: container)
        notifier = BudgetNotifier(center: notificationCenter ?? SystemNotificationCenter(),
                                  settings: settings, copy: Self.notificationCopy)
        alerts = BudgetAlertCoordinator(expenses: repository, budgets: budgets, notifier: notifier)
        if notificationCenter == nil { listenForNotificationTaps() }
    }

    /// Set before launch finishes, so a tap that launches the app reaches the router.
    private func listenForNotificationTaps() {
        let router = router
        let delegate = BudgetNotificationDelegate { payload in router.open(payload) }
        UNUserNotificationCenter.current().delegate = delegate
        notificationDelegate = delegate
    }

    /// The lock-screen text: generic, in the app's language, no amounts or store names.
    private static let notificationCopy: @Sendable (BudgetThreshold) -> BudgetNotificationCopy = { threshold in
        switch threshold {
        case .eighty:
            BudgetNotificationCopy(title: String(localized: "notification.budget.80.title"),
                                   body: String(localized: "notification.budget.80.body"))
        case .hundred:
            BudgetNotificationCopy(title: String(localized: "notification.budget.100.title"),
                                   body: String(localized: "notification.budget.100.body"))
        }
    }

    static func make() -> AppServices {
        let environment = ProcessInfo.processInfo.environment
        #if DEBUG
        // UI tests start from an empty ledger and leave nothing behind.
        if environment["KAKEIBO_IN_MEMORY_STORE"] == "1" {
            let photos = FileManager.default.temporaryDirectory.appendingPathComponent("UITestReceipts-\(UUID().uuidString)")
            let services = AppServices(
                container: try! KakeiboStore.makeContainer(inMemory: true),
                photoStore: try? PhotoStore(directory: photos),
                pipeline: makePipeline(environment),
                settings: AppSettings(defaults: uiTestDefaults()),
                notificationCenter: uiTestNotificationCenter(environment)
            )
            if environment["KAKEIBO_SEED_SAMPLE"] == "1" { services.seedSample() }
            if let insight = environment["KAKEIBO_SEED_INSIGHT"] { services.seedInsight(insight) }
            services.failSavesIfRequested(environment)
            return services
        }
        #endif
        protectAppData(environment)
        do {
            return AppServices(
                container: try KakeiboStore.makeContainer(),
                photoStore: try? PhotoStore.appDefault(),
                pipeline: makePipeline(environment)
            )
        } catch {
            // A store that cannot open is unrecoverable for a ledger app.
            fatalError("Could not open the expense store: \(error)")
        }
    }

    /// B-11: gives the store and receipt photos `.complete` protection, upgrading v1.0 files
    /// on the first launch after the update (and anything left weaker later). Runs before the
    /// store opens; safe on every launch. A failure never stops the app from opening: the
    /// files keep their old class and the next launch tries again.
    private static func protectAppData(_ environment: [String: String]) {
        #if DEBUG
        // `KAKEIBO_PROTECTION_REPORT=1`: print each file's class before and after, for the
        // device check (`xcrun devicectl device process launch --console …`).
        let report = environment["KAKEIBO_PROTECTION_REPORT"] == "1"
        if report, let folder = try? DataProtection.appDataDirectory() {
            print("[protection] before:\n" + DataProtection.report(folder).map(\.description).joined(separator: "\n"))
        }
        #endif
        do {
            let changed = try DataProtection.protectAppData()
            #if DEBUG
            if report { print("[protection] changed \(changed) items") }
            #endif
        } catch {
            #if DEBUG
            print("[protection] failed: \(error)")
            #endif
        }
        #if DEBUG
        if report, let folder = try? DataProtection.appDataDirectory() {
            print("[protection] after:\n" + DataProtection.report(folder).map(\.description).joined(separator: "\n"))
        }
        #endif
    }

    #if DEBUG
    /// Settings that start empty on every UI test launch, so one test's choices never reach another.
    private static func uiTestDefaults() -> UserDefaults {
        let name = "KakeiboUITests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// UI tests never show the iOS permission prompt (it would block the test). The permission
    /// comes from `KAKEIBO_NOTIFICATIONS`: `notDetermined` (default; the prompt answers
    /// `allowed`), `notDeterminedDeny` (the prompt answers `denied`), `allowed` or `denied`.
    private static func uiTestNotificationCenter(_ environment: [String: String]) -> InMemoryNotificationCenter {
        switch environment["KAKEIBO_NOTIFICATIONS"] {
        case "allowed": InMemoryNotificationCenter(status: .allowed)
        case "denied": InMemoryNotificationCenter(status: .denied)
        case "notDeterminedDeny": InMemoryNotificationCenter(status: .notDetermined, answer: .denied)
        default: InMemoryNotificationCenter(status: .notDetermined, answer: .allowed)
        }
    }

    /// `KAKEIBO_FAIL_SAVES=n`: the next n expense saves (or deletes) fail, so UI tests can show
    /// the failure panel and then succeed with "Try again". Set after the sample data is seeded.
    private func failSavesIfRequested(_ environment: [String: String]) {
        guard let value = environment["KAKEIBO_FAIL_SAVES"], var remaining = Int(value), remaining > 0 else { return }
        repository.beforeSave = {
            guard remaining > 0 else { return }
            remaining -= 1
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// Made-up expenses for UI tests and screenshots: four this month, one last month.
    private func seedSample() {
        let thisMonth = LedgerMonth(containing: .now)
        func day(_ month: LedgerMonth, _ d: Int) -> String { month.key + String(format: "-%02d", d) }
        let today = Int(DayKey.make(from: .now).suffix(2))!
        let samples: [(String, String, String?, Int, Int?, Int?, PaymentMethod, ExpenseCategory, Int)] = [
            (day(thisMonth, today), "まいばすけっと 架空町店", "My Basket", 1_310, 29, 72, .icCard, .groceries, 5),
            (day(thisMonth, today), "スターバックス", "Starbucks", 1_078, 98, nil, .credit, .dining, 0),
            (day(thisMonth, max(1, today - 1)), "JR東日本", nil, 2_150, nil, nil, .icCard, .transport, 0),
            (day(thisMonth, max(1, today - 1)), "ダイソー", "Daiso", 660, 60, nil, .cash, .household, 2),
            (day(thisMonth.previous, 28), "西松屋", "Nishimatsuya", 3_278, 298, nil, .qrPay, .kids, 4),
        ]
        for (dayKey, store, english, total, tax10, tax8, payment, category, items) in samples {
            let draft = ReceiptDraft(
                storeName: store, storeNameEn: english, dayKey: dayKey, totalYen: total, tax10Yen: tax10, tax8Yen: tax8,
                payment: payment, category: category,
                items: (0..<items).map { LineItemDraft(name: "品目\($0 + 1)", priceYen: total / max(items, 1)) }
            )
            _ = try? repository.create(from: draft, source: .manual)
        }
        // Last month had a ¥5,000 budget (now read-only). The repository only sets the current
        // month, so the sample writes the row directly.
        let past = BudgetMonth(monthKey: thisMonth.previous.key, budgetYen: 5_000, createdAt: .now, updatedAt: .now)
        container.mainContext.insert(past)
        try? container.mainContext.save()
    }
    #endif

    #if DEBUG
    /// `KAKEIBO_SEED_INSIGHT=over|onPace|closed|limited`: made-up months for the budget insight
    /// card and analysis (BI-04). Four usual months before this one (groceries, dining out and
    /// café visits), then:
    /// - `over`: this month ¥37,000 against a ¥30,000 budget (more dining out, a large one-off);
    /// - `onPace`: the same month against ¥40,000 (92%);
    /// - `closed`: last month spent the same ¥37,000 against a ¥30,000 budget; this month has none;
    /// - `limited`: `over` with no earlier months (limited history).
    private func seedInsight(_ kind: String) {
        let thisMonth = LedgerMonth(containing: .now)
        let today = Int(DayKey.make(from: .now).suffix(2))!
        func day(_ month: LedgerMonth, _ d: Int) -> String { month.key + String(format: "-%02d", min(max(d, 1), 28)) }
        func add(_ dayKey: String, _ store: String, _ english: String?, _ yen: Int, _ category: ExpenseCategory,
                 _ payment: PaymentMethod = .credit) {
            let draft = ReceiptDraft(storeName: store, storeNameEn: english, dayKey: dayKey, totalYen: yen,
                                     payment: payment, category: category)
            _ = try? repository.create(from: draft, source: .manual)
        }
        func usual(_ month: LedgerMonth) {
            for d in [3, 12, 21] { add(day(month, d), "まいばすけっと 架空町店", "My Basket", 10_000, .groceries, .icCard) }
            for d in [6, 18] { add(day(month, d), "さくら食堂", nil, 1_500, .dining) }
            for d in [9, 24] { add(day(month, d), "スターバックス", "Starbucks", 500, .dining) }
        }
        /// ¥37,000 up to `last`: usual groceries, more dining out, and a large one-off.
        func busy(_ month: LedgerMonth, last: Int) {
            add(day(month, 1), "まいばすけっと 架空町店", "My Basket", 10_000, .groceries, .icCard)
            for d in [last, last - 1, last - 2] { add(day(month, d), "さくら食堂", nil, 3_000, .dining) }
            add(day(month, last - 1), "ニトリ", "Nitori", 18_000, .household)
        }
        func setPastBudget(_ yen: Int, _ month: LedgerMonth) {
            container.mainContext.insert(BudgetMonth(monthKey: month.key, budgetYen: yen, createdAt: .now, updatedAt: .now))
            try? container.mainContext.save()
        }
        // The four months before the analysed one (this month, or last month for `closed`).
        if kind != "limited" {
            var month = kind == "closed" ? thisMonth.previous : thisMonth
            for _ in 0..<4 { month = month.previous; usual(month) }
        }
        switch kind {
        case "closed":
            busy(thisMonth.previous, last: 27)
            setPastBudget(30_000, thisMonth.previous)
            add(day(thisMonth, today), "スターバックス", "Starbucks", 500, .dining)
        case "onPace":
            busy(thisMonth, last: today)
            try? budgets.setBudget(40_000, for: thisMonth, now: .now)
        default:
            busy(thisMonth, last: today)
            try? budgets.setBudget(30_000, for: thisMonth, now: .now)
        }
    }
    #endif

    /// Deletes receipt photos no expense refers to (for example from a crash mid-save), and
    /// leftover exports and scanned pages (B-12).
    func cleanUp() {
        _ = try? repository.removeOrphanPhotos()
        var extra: [URL] = []
        #if DEBUG
        // Fixture capture files hold a receipt photo too.
        extra.append(FixtureCapture.directory)
        #endif
        if let folder = try? ScratchFiles.documentCameraDirectory() { Self.logProtection("leftover scanned pages", folder) }
        Self.logProtection("leftover exports", ScratchFiles.exportDirectory)
        try? ScratchFiles.cleanUpAtLaunch(extra: extra)
    }

    /// The scan has ended (saved, discarded or cancelled): VisionKit's copies of the pages go.
    func clearScannedPages() {
        if let folder = try? ScratchFiles.documentCameraDirectory() { Self.logProtection("scanned pages", folder) }
        try? ScratchFiles.clearScannedPages()
    }

    /// Debug `KAKEIBO_PROTECTION_REPORT=1`: prints the class of each file in `folder` just
    /// before it is deleted (scratch files never live long enough for the launch report).
    static func logProtection(_ label: String, _ folder: URL) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["KAKEIBO_PROTECTION_REPORT"] == "1" else { return }
        print("[protection] \(label) before removal:\n" + DataProtection.report(folder).map(\.description).joined(separator: "\n"))
        #endif
    }

    private static func makePipeline(_ environment: [String: String]) -> ExtractionPipeline {
        #if DEBUG
        // UI tests slow OCR down so the progress screen stays up long enough to check and cancel,
        // and turn the on-device model off so results do not depend on the machine.
        let refiner: any ReceiptRefiner = environment["KAKEIBO_NO_REFINER"] == "1" ? NoopRefiner() : ReceiptRefiners.automatic()
        if let text = environment["KAKEIBO_SCAN_OCR_DELAY"], let seconds = Double(text) {
            return ExtractionPipeline(ocr: DelayedOCR(base: VisionOCRService(), delay: .seconds(seconds)), refiner: refiner)
        }
        return ExtractionPipeline(refiner: refiner)
        #else
        return ExtractionPipeline()
        #endif
    }
}

#if DEBUG
import CoreGraphics
import KakeiboCore

/// Waits before reading, for UI tests only.
private struct DelayedOCR: OCRService {
    let base: any OCRService
    let delay: Duration

    func recognize(_ image: CGImage) async throws -> [TextObservation] {
        try await Task.sleep(for: delay)
        return try await base.recognize(image)
    }
}
#endif
