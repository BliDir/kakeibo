import KakeiboCore
import KakeiboScan
import KakeiboStore
import SwiftData
import SwiftUI

/// Root screen: a temporary expense list (T-40 builds the real ledger), the scan entry
/// and manual add, and the save confirmation.
struct ContentView: View {
    let services: AppServices

    @State private var session: ScanSession
    @State private var editor: EditorItem?
    @State private var banner: Banner?
    #if DEBUG
    @State private var showTokens = ProcessInfo.processInfo.environment["KAKEIBO_SHOW_TOKENS"] == "1"
    #endif

    init(services: AppServices) {
        self.services = services
        _session = State(initialValue: ScanSession(pipeline: services.pipeline))
    }

    var body: some View {
        NavigationStack {
            TemporaryExpenseList { expense in
                editor = EditorItem(form: ReviewForm(editing: expense))
            }
            .navigationTitle("app.title")
            #if DEBUG
            .toolbar {
                Button { showTokens = true } label: { Image(systemName: "hammer") }
                    .accessibilityLabel(Text(verbatim: "Design tokens"))
                    .accessibilityIdentifier("debug.tokens")
            }
            .sheet(isPresented: $showTokens) { DesignTokensView() }
            #endif
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    ScanEntryButtons(session: session)
                    Button {
                        editor = EditorItem(form: ReviewForm(manualOn: .now))
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
                .padding(.bottom, 16)
            }
        }
        .overlay(alignment: .top) {
            if let banner { BannerView(banner: banner).padding(.top, 8) }
        }
        .fullScreenCover(isPresented: Binding(
            get: { session.phase != .idle },
            set: { if !$0 { session.cancel() } }
        )) {
            ScanFlowView(session: session, services: services) { total in show(.saved(total)) }
        }
        .fullScreenCover(item: $editor) { item in
            ReviewView(form: item.form, services: services) { outcome in
                editor = nil
                switch outcome {
                case .saved(let total): show(.saved(total))
                case .deleted: show(.deleted)
                case .discarded: break
                }
            }
        }
        #if DEBUG
        .task { startDebugScanIfRequested() }
        #endif
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

/// Temporary list of saved expenses so they can be opened and edited. T-40 replaces it.
private struct TemporaryExpenseList: View {
    @Query(sort: [SortDescriptor(\Expense.dayKey, order: .reverse), SortDescriptor(\Expense.createdAt, order: .reverse)])
    private var expenses: [Expense]
    let onSelect: (Expense) -> Void

    var body: some View {
        if expenses.isEmpty {
            ContentUnavailableView(
                "ledger.empty.title",
                systemImage: "doc.text.viewfinder",
                description: Text("ledger.empty.message")
            )
        } else {
            List(expenses) { expense in
                Button { onSelect(expense) } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            if expense.storeName.isEmpty {
                                Text("ledger.noStore").foregroundStyle(Theme.secondaryText)
                            } else {
                                Text(verbatim: expense.storeName).foregroundStyle(Theme.text)
                            }
                            Text(verbatim: expense.dayKey).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Text(verbatim: Yen.format(expense.totalYen))
                            .font(.amount)
                            .foregroundStyle(Theme.text)
                    }
                }
                .accessibilityIdentifier("ledger.row")
            }
        }
    }
}

#Preview {
    ContentView(services: AppServices.make())
}
