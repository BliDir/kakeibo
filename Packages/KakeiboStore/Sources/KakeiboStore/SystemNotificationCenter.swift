import Foundation
import KakeiboCore
import UserNotifications

/// The live `BudgetNotificationCenter`: iOS local notifications, nothing remote.
///
/// Create it only in the app: `UNUserNotificationCenter.current()` needs an app bundle and
/// traps under `swift test`. Tests use `InMemoryNotificationCenter`.
public struct SystemNotificationCenter: BudgetNotificationCenter {
    // Read each time rather than stored: the SDK does not mark the center `Sendable`
    // (Apple documents it as thread-safe), and `current()` always returns the same one.
    private var center: UNUserNotificationCenter { .current() }

    public init() {}

    public func authorization() async -> NotificationAuthorization {
        Self.authorization(for: await center.notificationSettings().authorizationStatus)
    }

    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func add(_ request: BudgetNotificationRequest) async throws {
        try await center.add(Self.systemRequest(for: request))
    }

    public func pendingRequestIDs() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func deliveredRequestIDs() async -> [String] {
        await center.deliveredNotifications().map(\.request.identifier)
    }

    public func removePending(ids: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    public func removeDelivered(ids: [String]) async {
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    // MARK: - Mapping (tested)

    static func authorization(for status: UNAuthorizationStatus) -> NotificationAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized, .provisional: return .allowed
        case .denied: return .denied
        default:
            // `.ephemeral` (App Clips) exists only on iOS, and `swift test` runs on macOS.
            #if os(iOS)
            if status == .ephemeral { return .allowed }
            #endif
            return .denied
        }
    }

    /// A request shown now (no trigger), under the stable ID, so a repeat replaces it.
    static func systemRequest(for request: BudgetNotificationRequest) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = request.payload.userInfo
        // Group budget alerts together in Notification Center.
        content.threadIdentifier = "budget"
        return UNNotificationRequest(identifier: request.id, content: content, trigger: nil)
    }
}

/// Handles budget notifications while the app runs: hides the iOS banner in the foreground
/// (the app shows its own in-app banner for the same event) and opens the budget on a tap.
///
/// Set it as `UNUserNotificationCenter.current().delegate` before launch finishes, so a tap
/// that launches the app is not missed, and keep a strong reference (the delegate is weak).
public final class BudgetNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let onOpen: @MainActor @Sendable (BudgetNotificationPayload) -> Void

    public init(onOpen: @escaping @MainActor @Sendable (BudgetNotificationPayload) -> Void) {
        self.onOpen = onOpen
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Self.presentationOptions(for: notification.request.content.userInfo)
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let payload = BudgetNotificationPayload(userInfo: response.notification.request.content.userInfo) else { return }
        await onOpen(payload)
    }

    /// Budget alerts show no system banner in the foreground; anything else shows normally.
    static func presentationOptions(for userInfo: [AnyHashable: Any]) -> UNNotificationPresentationOptions {
        BudgetNotificationPayload(userInfo: userInfo) == nil ? [.banner, .list, .sound] : []
    }
}
