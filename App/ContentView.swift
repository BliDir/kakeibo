import KakeiboCore
import KakeiboScan
import KakeiboStore
import SwiftUI

/// Root screen: the ledger, the scan entry and manual add, and the save confirmation.
struct ContentView: View {
    let services: AppServices

    @State private var session: ScanSession
    @State private var ledger: LedgerModel
    @State private var editor: EditorItem?
    /// Screens pushed on the ledger tab: expense details, the budget analysis, a filtered ledger.
    @State private var ledgerPath: [LedgerRoute] = []
    @State private var banner: Banner?
    @State private var tab: AppTab = .ledger
    @Environment(\.scenePhase) private var scenePhase
    @State private var settingsModel: SettingsModel
    /// A saved expense to show once the current full-screen cover has gone
    /// (the duplicate warning's "View saved entry"). Two covers cannot be presented at the same time.
    @State private var openAfterDismiss: Expense?
    /// The read error's "Enter manually": open an empty manual form once the scan cover has gone.
    @State private var manualAfterDismiss = false
    #if DEBUG
    @State private var showTokens = ProcessInfo.processInfo.environment["KAKEIBO_SHOW_TOKENS"] == "1"
    #endif

    init(services: AppServices) {
        self.services = services
        _session = State(initialValue: ScanSession(pipeline: services.pipeline))
        _ledger = State(initialValue: LedgerModel(repository: services.repository, budgets: services.budgets))
        _settingsModel = State(initialValue: SettingsModel(
            settings: services.settings, photoStore: services.photoStore, info: Bundle.main.infoDictionary ?? [:]
        ))
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("tab.ledger", systemImage: "list.bullet.rectangle", value: AppTab.ledger) {
                ledgerTab
            }
            .accessibilityIdentifier("tab.ledger")
            Tab("tab.summary", systemImage: "chart.bar.xaxis", value: AppTab.summary) {
                SummaryView(model: ledger)
            }
            .accessibilityIdentifier("tab.summary")
            Tab("tab.settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView(model: settingsModel, notifier: services.notifier)
            }
            .accessibilityIdentifier("tab.settings")
        }
        .tint(Theme.accent)
        #if DEBUG
        .sheet(isPresented: $showTokens) { DesignTokensView() }
        #endif
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let banner { BannerView(banner: banner) }
                // A budget alert event: the one banner for it (the iOS one is hidden in the foreground).
                if let alert = services.alerts.banner {
                    BudgetAlertBannerView(banner: alert) {
                        withAnimation { services.alerts.dismissBanner() }
                    }
                }
            }
            .padding(.top, 8)
            .animation(.default, value: services.alerts.banner)
        }
        .fullScreenCover(isPresented: Binding(
            get: { session.phase != .idle },
            set: { if !$0 { session.cancel() } }
        ), onDismiss: openPendingExpense) {
            ScanFlowView(
                session: session,
                services: services,
                onSaved: { total in show(.saved(total)) },
                onViewSaved: { expense in openAfterDismiss = expense },
                onManual: { manualAfterDismiss = true }
            )
        }
        .fullScreenCover(item: $editor, onDismiss: openPendingExpense) { item in
            ReviewView(form: item.form, services: services) { outcome in
                editor = nil
                switch outcome {
                case .saved(let total): show(.saved(total))
                case .discarded: break
                case .viewSaved(let expense): openAfterDismiss = expense
                }
            }
        }
        // Budgets: "today" changes the weekly allowance and maybe the month. Refresh when the app
        // comes back, and once at each Tokyo midnight while it is open; nothing runs in the background.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            ledger.refreshForCurrentDate()
            // Re-check this month's alerts: retries an unconfirmed one, drops ones for an ended month.
            services.alerts.reconcile()
            // Notification permission can change in iOS Settings while the app is away.
            Task { await services.notifier.refreshAuthorization() }
        }
        // A tapped budget alert (also one that launched the app) opens this month's budget.
        .onChange(of: services.router.openBudget, initial: true) { _, payload in
            guard payload != nil else { return }
            services.router.openBudget = nil
            openCurrentBudget()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                let wait = Calendar.kakeibo.startOfNextDay(after: .now).timeIntervalSinceNow + 1
                try? await Task.sleep(for: .seconds(max(wait, 1)))
                guard !Task.isCancelled else { return }
                ledger.refreshForCurrentDate()
                services.alerts.reconcile()
            }
        }
        #if DEBUG
        .task { startDebugScanIfRequested() }
        #endif
    }

    /// The ledger, with Scan / Photo / Manual at the top of its content. A row opens the
    /// expense's details; Edit there opens the form over it.
    private var ledgerTab: some View {
        NavigationStack(path: $ledgerPath) {
            LedgerView(
                model: ledger,
                session: session,
                photoStore: services.photoStore,
                onSelect: { expense in ledgerPath = [.expense(expense)] },
                onManual: openManualEntry,
                onShowTokens: showTokensAction,
                onOpenAlertSettings: { tab = .settings },
                onSeeAnalysis: { ledgerPath = [.analysis] }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LedgerRoute.self) { route in
                switch route {
                case .expense(let expense):
                    ExpenseDetailView(
                        expense: expense,
                        services: services,
                        onEdit: { editor = EditorItem(form: ReviewForm(editing: $0)) },
                        onDeleted: {
                            // Back to where the details were opened from (the ledger or a filtered ledger).
                            if !ledgerPath.isEmpty { ledgerPath.removeLast() }
                            show(.deleted)
                        }
                    )
                case .analysis:
                    BudgetAnalysisView(model: ledger) { target in ledgerPath.append(.filtered(target)) }
                case .filtered(let target):
                    FilteredLedgerView(model: ledger, target: target, photoStore: services.photoStore) { expense in
                        ledgerPath.append(.expense(expense))
                    }
                }
            }
        }
        .tint(Theme.accent)
    }

    private var showTokensAction: (() -> Void)? {
        #if DEBUG
        { showTokens = true }
        #else
        nil
        #endif
    }

    /// The ledger tab on the current month, where the budget progress card is at the top.
    /// The scan or edit screen, if open, stays open: closing it could lose the user's work.
    private func openCurrentBudget() {
        tab = .ledger
        ledgerPath.removeAll()
        ledger.show(ledger.currentMonth)
    }

    private func openManualEntry() {
        editor = EditorItem(form: ReviewForm(manualOn: .now, payment: services.settings.defaultPayment))
    }

    private func openPendingExpense() {
        // Whichever cover closed, no scan is in progress now (B-12).
        services.clearScannedPages()
        if manualAfterDismiss {
            manualAfterDismiss = false
            openManualEntry()
            return
        }
        guard let expense = openAfterDismiss else { return }
        openAfterDismiss = nil
        tab = .ledger
        ledgerPath = [.expense(expense)]
    }

    private func show(_ banner: Banner) {
        withAnimation { self.banner = banner }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { if self.banner == banner { self.banner = nil } }
        }
    }

    #if DEBUG
    /// UI tests pass a receipt image path, so the scan flow can run on the simulator
    /// without the photo picker. Same path as a library photo.
    private func startDebugScanIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["KAKEIBO_SCAN_IMAGE_PATH"],
              let data = FileManager.default.contents(atPath: path) else { return }
        session.start(imageData: data)
    }
    #endif
}

/// A screen pushed on the ledger tab's navigation stack.
enum LedgerRoute: Hashable {
    case expense(Expense)
    /// Why the shown month is over budget (BI-04).
    case analysis
    /// The shown month's expenses in one driver's category or store.
    case filtered(InsightTarget)
}

enum AppTab: Hashable {
    case ledger
    case summary
    case settings
}

/// A form presented for manual add or edit.
private struct EditorItem: Identifiable {
    let id = UUID()
    let form: ReviewForm
}

enum Banner: Equatable {
    case saved(Int)
    case deleted
}

/// The confirmation shown after returning to the ledger.
private struct BannerView: View {
    let banner: Banner

    var body: some View {
        Label {
            switch banner {
            case .saved(let total):
                Text("toast.saved \(LedgerFormat.yen(total))")
                    .accessibilityLabel(Text("toast.saved \(LedgerFormat.spokenYen(total))"))
            case .deleted: Text("toast.deleted")
            }
        } icon: {
            Image(systemName: "checkmark.circle.fill")
        }
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        // Inverted, as in the design: ground-colored text on the text color.
        .background(Theme.text, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .foregroundStyle(Theme.groundLight)
        .shadow(color: Theme.shadow, radius: 12, y: 6)
        .padding(.horizontal, Spacing.l)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityIdentifier("banner")
    }
}

#Preview {
    ContentView(services: AppServices.make())
}
