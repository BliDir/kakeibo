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
    @State private var banner: Banner?
    @State private var tab: AppTab = .ledger
    @Environment(\.scenePhase) private var scenePhase
    @State private var settingsModel: SettingsModel
    /// A saved expense to open once the current full-screen cover has gone
    /// (from the duplicate warning). Two covers cannot be presented at the same time.
    @State private var openAfterDismiss: Expense?
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
                onViewSaved: { expense in openAfterDismiss = expense }
            )
        }
        .fullScreenCover(item: $editor, onDismiss: openPendingExpense) { item in
            ReviewView(form: item.form, services: services) { outcome in
                editor = nil
                switch outcome {
                case .saved(let total): show(.saved(total))
                case .deleted: show(.deleted)
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

    /// The ledger, with Scan / Photo / Manual at the top of its content.
    private var ledgerTab: some View {
        LedgerView(
            model: ledger,
            session: session,
            photoStore: services.photoStore,
            onSelect: { expense in editor = EditorItem(form: ReviewForm(editing: expense)) },
            onManual: {
                editor = EditorItem(form: ReviewForm(manualOn: .now, payment: services.settings.defaultPayment))
            },
            onShowTokens: showTokensAction
        )
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
        ledger.show(ledger.currentMonth)
    }

    private func openPendingExpense() {
        guard let expense = openAfterDismiss else { return }
        openAfterDismiss = nil
        editor = EditorItem(form: ReviewForm(editing: expense))
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
