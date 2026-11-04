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
        _ledger = State(initialValue: LedgerModel(repository: services.repository))
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
                SettingsView(model: settingsModel)
            }
            .accessibilityIdentifier("tab.settings")
        }
        .tint(Theme.accent)
        #if DEBUG
        .sheet(isPresented: $showTokens) { DesignTokensView() }
        #endif
        .overlay(alignment: .top) {
            if let banner { BannerView(banner: banner).padding(.top, 8) }
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
        #if DEBUG
        .task { startDebugScanIfRequested() }
        #endif
    }

    /// The ledger with the scan and manual-add buttons.
    private var ledgerTab: some View {
        LedgerView(
            model: ledger,
            photoStore: services.photoStore,
            onSelect: { expense in editor = EditorItem(form: ReviewForm(editing: expense)) },
            onShowTokens: showTokensAction
        )
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                ScanEntryButtons(session: session)
                Button {
                    editor = EditorItem(form: ReviewForm(manualOn: .now, payment: services.settings.defaultPayment))
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 54, height: 54)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().stroke(Theme.border))
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel(Text("ledger.add"))
                .accessibilityIdentifier("ledger.add")
            }
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
        }
    }

    private var showTokensAction: (() -> Void)? {
        #if DEBUG
        { showTokens = true }
        #else
        nil
        #endif
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
            case .saved(let total): Text("toast.saved \(Yen.format(total))")
            case .deleted: Text("toast.deleted")
            }
        } icon: {
            Image(systemName: "checkmark.circle.fill")
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.text, in: Capsule())
        .foregroundStyle(Theme.surface)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityIdentifier("banner")
    }
}

#Preview {
    ContentView(services: AppServices.make())
}
