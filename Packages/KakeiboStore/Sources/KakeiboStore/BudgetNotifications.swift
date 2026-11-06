import Foundation
import KakeiboCore
import Observation

// Local budget alert notifications (v1.1, B-06).
//
// `BudgetNotifier` is what the app and the alert coordinator (B-07) use: the user's opt-in,
// the real iOS permission, sending and cancelling. It talks to the system only through
// `BudgetNotificationCenter`, so it is tested with `InMemoryNotificationCenter`; the live
// adapter is `SystemNotificationCenter`. Local notifications only: no server, push or network.
//
// Rules (Kakeibo iOS v1.1 release plan):
// - Alerts are off until the user turns them on. Permission is asked only then, never at launch.
// - Lock-screen copy is generic: no amounts, store names or receipt details.
// - Each month and threshold has one stable request ID (`budget-<yyyy-MM>-<80|100>`), so a
//   repeated send replaces rather than duplicates.
// - Handing a request to iOS is not delivery: iOS may still hold it back (Focus, Summary,
//   permission changed). Nothing here claims an alert was seen.

/// What iOS currently allows for this app's notifications.
public enum NotificationAuthorization: Sendable, Equatable {
    /// The user has not been asked yet.
    case notDetermined
    /// Notifications can be shown (also provisional and ephemeral authorization).
    case allowed
    /// Turned off in iOS Settings, or the user declined the prompt.
    case denied
}

/// What a budget notification carries so a tap can open the budget. Also its request ID.
public struct BudgetNotificationPayload: Sendable, Equatable, Hashable {
    static let routeKey = "route"
    static let routeValue = "budget"
    static let monthKey = "month"
    static let thresholdKey = "threshold"
    static let idPrefix = "budget-"

    /// `yyyy-MM`, Tokyo.
    public let monthKey: String
    public let threshold: BudgetThreshold

    public init(monthKey: String, threshold: BudgetThreshold) {
        self.monthKey = monthKey
        self.threshold = threshold
    }

    /// The stable request ID, the same one `BudgetAlertIntent` stores.
    public var requestID: String {
        BudgetAlertIntent.requestID(monthKey: monthKey, threshold: threshold)
    }

    /// The notification's `userInfo`: the route to open and which alert it was.
    public var userInfo: [String: String] {
        [Self.routeKey: Self.routeValue, Self.monthKey: monthKey, Self.thresholdKey: String(threshold.rawValue)]
    }

    /// Reads a tapped or presented notification's `userInfo`; nil if it is not a budget alert.
    public init?(userInfo: [AnyHashable: Any]) {
        guard userInfo[Self.routeKey] as? String == Self.routeValue,
              let month = userInfo[Self.monthKey] as? String, Self.isMonthKey(month),
              let raw = (userInfo[Self.thresholdKey] as? String).flatMap(Int.init),
              let threshold = BudgetThreshold(rawValue: raw) else { return nil }
        self.init(monthKey: month, threshold: threshold)
    }

    /// Reads a request ID such as `budget-2026-11-80`; nil for any other ID.
    public init?(requestID: String) {
        guard requestID.hasPrefix(Self.idPrefix) else { return nil }
        let rest = requestID.dropFirst(Self.idPrefix.count)
        guard let dash = rest.lastIndex(of: "-") else { return nil }
        let month = String(rest[..<dash])
        guard Self.isMonthKey(month), let raw = Int(rest[rest.index(after: dash)...]),
              let threshold = BudgetThreshold(rawValue: raw) else { return nil }
        self.init(monthKey: month, threshold: threshold)
    }

    private static func isMonthKey(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
              Int(parts[0]) != nil, let month = Int(parts[1]) else { return false }
        return (1...12).contains(month)
    }
}

/// One notification to hand to iOS, delivered now (no trigger).
public struct BudgetNotificationRequest: Sendable, Equatable {
    public let payload: BudgetNotificationPayload
    public let title: String
    public let body: String

    public var id: String { payload.requestID }
}

/// The lock-screen text for a threshold: generic, no amounts or store names.
/// The app supplies it from `Localizable.xcstrings` (a package cannot compile a String Catalog).
public struct BudgetNotificationCopy: Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// The system's notification center, behind a protocol so it can be faked in tests.
public protocol BudgetNotificationCenter: Sendable {
    func authorization() async -> NotificationAuthorization
    /// Shows the iOS permission prompt (only the first time). True if allowed.
    func requestAuthorization() async throws -> Bool
    func add(_ request: BudgetNotificationRequest) async throws
    func pendingRequestIDs() async -> [String]
    func deliveredRequestIDs() async -> [String]
    func removePending(ids: [String]) async
    func removeDelivered(ids: [String]) async
}

/// The user's budget alert setting and the system permission, and the way to send alerts.
@MainActor
@Observable
public final class BudgetNotifier {
    /// What happened to a send. Never "delivered": iOS decides that.
    public enum SendResult: Sendable, Equatable {
        /// iOS accepted the request; it may still not be shown.
        case handedToSystem
        /// Alerts are off in the app, or iOS does not allow notifications. Nothing was queued.
        case notAllowed
        /// iOS refused the request.
        case failed
    }

    private let center: any BudgetNotificationCenter
    private let settings: AppSettings
    private let copy: @Sendable (BudgetThreshold) -> BudgetNotificationCopy

    /// The real iOS permission, as last read. Read again with `refreshAuthorization()`.
    public private(set) var authorization: NotificationAuthorization = .notDetermined
    /// Set when asking iOS for permission failed; cleared on the next try.
    public private(set) var requestFailed = false
    /// True while the permission prompt is up.
    public private(set) var isRequesting = false

    public init(center: any BudgetNotificationCenter, settings: AppSettings,
                copy: @escaping @Sendable (BudgetThreshold) -> BudgetNotificationCopy) {
        self.center = center
        self.settings = settings
        self.copy = copy
    }

    /// The user's choice in Settings. Off by default.
    public var isEnabled: Bool { settings.budgetAlertsEnabled }

    /// Alerts may be sent: the user turned them on and iOS allows them.
    /// This is `notificationsAllowed` for `BudgetAlertPolicy`.
    public var canSend: Bool { isEnabled && authorization == .allowed }

    /// The user wants alerts but iOS has them off: show the way to iOS Settings.
    public var needsSystemSettings: Bool { isEnabled && authorization == .denied }

    /// Reads the current iOS permission (it can change in iOS Settings at any time).
    public func refreshAuthorization() async {
        authorization = await center.authorization()
    }

    /// Turns budget alerts on or off. Turning them on is the only place the iOS prompt is
    /// shown, and only if the user has never answered it. Turning them off cancels alerts
    /// not yet shown; nothing is kept to send later.
    public func setEnabled(_ enabled: Bool) async {
        settings.budgetAlertsEnabled = enabled
        requestFailed = false
        guard enabled else {
            await cancelAllPending()
            await refreshAuthorization()
            return
        }
        await refreshAuthorization()
        guard authorization == .notDetermined else { return }
        isRequesting = true
        defer { isRequesting = false }
        do {
            _ = try await center.requestAuthorization()
        } catch {
            requestFailed = true
        }
        await refreshAuthorization()
    }

    /// Sends the alert for a month's threshold now, if alerts are allowed. Permission is read
    /// again first, so a change in iOS Settings since the last refresh is respected.
    @discardableResult
    public func send(_ threshold: BudgetThreshold, for month: LedgerMonth) async -> SendResult {
        await refreshAuthorization()
        guard canSend else { return .notAllowed }
        let text = copy(threshold)
        let request = BudgetNotificationRequest(
            payload: BudgetNotificationPayload(monthKey: month.key, threshold: threshold),
            title: text.title, body: text.body
        )
        do {
            try await center.add(request)
            return .handedToSystem
        } catch {
            return .failed
        }
    }

    /// Cancels alerts for a month that iOS has not shown yet.
    public func cancelPending(_ thresholds: Set<BudgetThreshold>, for month: LedgerMonth) async {
        guard !thresholds.isEmpty else { return }
        let ids = thresholds.sorted().map { BudgetNotificationPayload(monthKey: month.key, threshold: $0).requestID }
        await center.removePending(ids: ids)
    }

    /// Budget alerts iOS still holds to show, for reconciling with stored intents.
    public func pendingAlerts() async -> [BudgetNotificationPayload] {
        await center.pendingRequestIDs().compactMap(BudgetNotificationPayload.init(requestID:))
    }

    /// Budget alerts iOS has shown and still lists in Notification Center.
    public func deliveredAlerts() async -> [BudgetNotificationPayload] {
        await center.deliveredRequestIDs().compactMap(BudgetNotificationPayload.init(requestID:))
    }

    private func cancelAllPending() async {
        let ids = await pendingAlerts().map(\.requestID)
        if !ids.isEmpty { await center.removePending(ids: ids) }
    }
}

/// A notification center that keeps everything in memory: for tests, previews and UI tests.
public actor InMemoryNotificationCenter: BudgetNotificationCenter {
    public enum Failure: Error { case refused }

    public private(set) var status: NotificationAuthorization
    /// What the user answers when asked.
    public var answer: NotificationAuthorization
    /// Make `requestAuthorization` throw.
    public var failRequest = false
    /// Make `add` throw.
    public var failAdd = false
    public private(set) var requestCount = 0
    public private(set) var pending: [BudgetNotificationRequest] = []
    public private(set) var delivered: [String] = []
    /// Every request ID handed over by `add`, in order, repeats included.
    public private(set) var added: [String] = []

    public init(status: NotificationAuthorization = .notDetermined, answer: NotificationAuthorization = .allowed) {
        self.status = status
        self.answer = answer
    }

    public func setStatus(_ status: NotificationAuthorization) { self.status = status }
    public func setAnswer(_ answer: NotificationAuthorization) { self.answer = answer }
    public func setFailRequest(_ fail: Bool) { failRequest = fail }
    public func setFailAdd(_ fail: Bool) { failAdd = fail }

    /// Moves pending requests to delivered, as iOS would.
    public func deliverAll() {
        delivered += pending.map(\.id)
        pending.removeAll()
    }

    public func authorization() -> NotificationAuthorization { status }

    public func requestAuthorization() throws -> Bool {
        requestCount += 1
        if failRequest { throw Failure.refused }
        // iOS asks only once; later calls return the stored answer.
        if status == .notDetermined { status = answer }
        return status == .allowed
    }

    public func add(_ request: BudgetNotificationRequest) throws {
        if failAdd { throw Failure.refused }
        added.append(request.id)
        // The same ID replaces the earlier request, as in iOS.
        pending.removeAll { $0.id == request.id }
        pending.append(request)
    }

    public func pendingRequestIDs() -> [String] { pending.map(\.id) }
    public func deliveredRequestIDs() -> [String] { delivered }

    public func removePending(ids: [String]) {
        pending.removeAll { ids.contains($0.id) }
    }

    public func removeDelivered(ids: [String]) {
        delivered.removeAll { ids.contains($0) }
    }
}
