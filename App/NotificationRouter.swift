import KakeiboStore
import Observation

/// Where a tapped notification asks the app to go. `ContentView` acts on it and clears it.
/// It can be set before any screen exists (a tap that launches the app).
@MainActor
@Observable
final class NotificationRouter {
    /// A budget alert was tapped: show the current month's budget progress.
    var openBudget: BudgetNotificationPayload?

    func open(_ payload: BudgetNotificationPayload) {
        openBudget = payload
    }
}
