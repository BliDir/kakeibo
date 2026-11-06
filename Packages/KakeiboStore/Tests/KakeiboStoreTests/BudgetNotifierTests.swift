import Foundation
import KakeiboCore
import Testing
import UserNotifications
@testable import KakeiboStore

@MainActor
@Suite struct BudgetNotifierTests {
    let suiteName = "BudgetNotifierTests-\(UUID().uuidString)"
    let november = LedgerMonth(year: 2026, month: 11)

    private func make(_ center: InMemoryNotificationCenter, enabled: Bool = false) -> (BudgetNotifier, AppSettings) {
        let settings = AppSettings(defaults: UserDefaults(suiteName: suiteName)!)
        settings.budgetAlertsEnabled = enabled
        let notifier = BudgetNotifier(center: center, settings: settings) { threshold in
            BudgetNotificationCopy(title: "title-\(threshold.rawValue)", body: "body-\(threshold.rawValue)")
        }
        return (notifier, settings)
    }

    // MARK: Opt-in and permission

    @Test func alertsStartOffAndNothingIsAsked() async {
        let center = InMemoryNotificationCenter()
        let (notifier, _) = make(center)
        await notifier.refreshAuthorization()
        #expect(!notifier.isEnabled)
        #expect(!notifier.canSend)
        #expect(notifier.authorization == .notDetermined)
        #expect(await center.requestCount == 0, "no prompt at launch")
        #expect(await notifier.send(.eighty, for: november) == .notAllowed)
        #expect(await center.pendingRequestIDs().isEmpty)
    }

    @Test func turningOnAsksOnceAndRemembersTheChoice() async {
        let center = InMemoryNotificationCenter(answer: .allowed)
        let (notifier, _) = make(center)
        await notifier.setEnabled(true)
        #expect(await center.requestCount == 1)
        #expect(notifier.authorization == .allowed)
        #expect(notifier.canSend)
        #expect(!notifier.needsSystemSettings)

        // Off and on again: iOS already has an answer, so no second prompt.
        await notifier.setEnabled(false)
        await notifier.setEnabled(true)
        #expect(await center.requestCount == 1)

        // The choice survives a relaunch.
        #expect(AppSettings(defaults: UserDefaults(suiteName: suiteName)!).budgetAlertsEnabled)
    }

    @Test func declinedPromptLeavesAlertsOnButShowsTheSettingsLink() async {
        let center = InMemoryNotificationCenter(answer: .denied)
        let (notifier, _) = make(center)
        await notifier.setEnabled(true)
        #expect(notifier.isEnabled, "the user's choice stays")
        #expect(notifier.authorization == .denied)
        #expect(!notifier.canSend)
        #expect(notifier.needsSystemSettings)
        #expect(await notifier.send(.eighty, for: november) == .notAllowed)
    }

    @Test func alreadyDeniedIsNotAskedAgain() async {
        let center = InMemoryNotificationCenter(status: .denied)
        let (notifier, _) = make(center)
        await notifier.setEnabled(true)
        #expect(await center.requestCount == 0, "iOS would not show the prompt again")
        #expect(notifier.needsSystemSettings)
    }

    @Test func deniedWithAlertsOffShowsNoSettingsLink() async {
        let center = InMemoryNotificationCenter(status: .denied)
        let (notifier, _) = make(center)
        await notifier.refreshAuthorization()
        #expect(!notifier.needsSystemSettings)
    }

    @Test func aFailedPromptIsReportedAndCanBeRetried() async {
        let center = InMemoryNotificationCenter()
        await center.setFailRequest(true)
        let (notifier, _) = make(center)
        await notifier.setEnabled(true)
        #expect(notifier.requestFailed)
        #expect(notifier.authorization == .notDetermined)
        #expect(!notifier.isRequesting)

        await center.setFailRequest(false)
        await notifier.setEnabled(true)
        #expect(!notifier.requestFailed)
        #expect(notifier.canSend)
    }

    @Test func permissionChangedInSettingsIsPickedUp() async {
        let center = InMemoryNotificationCenter(status: .allowed)
        let (notifier, _) = make(center, enabled: true)
        await notifier.refreshAuthorization()
        #expect(notifier.canSend)

        // Turned off in iOS Settings while the app was in the background.
        await center.setStatus(.denied)
        await notifier.refreshAuthorization()
        #expect(!notifier.canSend)
        #expect(notifier.needsSystemSettings)

        // Turned back on.
        await center.setStatus(.allowed)
        await notifier.refreshAuthorization()
        #expect(notifier.canSend)
    }

    // MARK: Sending

    @Test func sendUsesTheStableIDGenericCopyAndBudgetPayload() async {
        let center = InMemoryNotificationCenter(status: .allowed)
        let (notifier, _) = make(center, enabled: true)
        #expect(await notifier.send(.eighty, for: november) == .handedToSystem)
        let request = try! #require(await center.pending.first)
        #expect(request.id == "budget-2026-11-80")
        #expect(request.id == BudgetAlertIntent.requestID(monthKey: "2026-11", threshold: .eighty))
        #expect(request.title == "title-80")
        #expect(request.body == "body-80")
        #expect(request.payload.userInfo == ["route": "budget", "month": "2026-11", "threshold": "80"])
    }

    @Test func repeatedSendReplacesInsteadOfDuplicating() async {
        let center = InMemoryNotificationCenter(status: .allowed)
        let (notifier, _) = make(center, enabled: true)
        await notifier.send(.hundred, for: november)
        await notifier.send(.hundred, for: november)
        #expect(await center.pendingRequestIDs() == ["budget-2026-11-100"])
    }

    @Test func sendRereadsPermissionFirst() async {
        let center = InMemoryNotificationCenter(status: .allowed)
        let (notifier, _) = make(center, enabled: true)
        await notifier.refreshAuthorization()
        await center.setStatus(.denied)
        #expect(await notifier.send(.eighty, for: november) == .notAllowed)
        #expect(await center.pendingRequestIDs().isEmpty, "nothing queued for later")
    }

    @Test func aSystemErrorIsAFailureNotADelivery() async {
        let center = InMemoryNotificationCenter(status: .allowed)
        await center.setFailAdd(true)
        let (notifier, _) = make(center, enabled: true)
        #expect(await notifier.send(.eighty, for: november) == .failed)
    }

    // MARK: Cancelling and querying

    @Test func cancelRemovesOnlyThatMonthsThresholds() async {
        let center = InMemoryNotificationCenter(status: .allowed)
        let (notifier, _) = make(center, enabled: true)
        await notifier.send(.eighty, for: november)
        await notifier.send(.hundred, for: november)
        await notifier.send(.eighty, for: november.next)
        await notifier.cancelPending([.eighty], for: november)
        #expect(Set(await center.pendingRequestIDs()) == ["budget-2026-11-100", "budget-2026-12-80"])
    }

    @Test func turningOffCancelsPendingAlertsOnly() async {
        let center = InMemoryNotificationCenter(status: .allowed)
        let (notifier, _) = make(center, enabled: true)
        await notifier.send(.eighty, for: november)
        await center.deliverAll()
        await notifier.send(.hundred, for: november)
        await notifier.setEnabled(false)
        #expect(await center.pendingRequestIDs().isEmpty)
        #expect(await center.deliveredRequestIDs() == ["budget-2026-11-80"], "shown alerts stay in Notification Center")
        #expect(!notifier.canSend)
    }

    @Test func queriesListOnlyBudgetAlerts() async {
        let center = InMemoryNotificationCenter(status: .allowed)
        let (notifier, _) = make(center, enabled: true)
        await notifier.send(.eighty, for: november)
        await center.deliverAll()
        await notifier.send(.hundred, for: november)
        #expect(await notifier.pendingAlerts() == [BudgetNotificationPayload(monthKey: "2026-11", threshold: .hundred)])
        #expect(await notifier.deliveredAlerts() == [BudgetNotificationPayload(monthKey: "2026-11", threshold: .eighty)])
    }
}

@Suite struct BudgetNotificationPayloadTests {
    @Test func requestIDRoundTrips() {
        for threshold in BudgetThreshold.allCases {
            let payload = BudgetNotificationPayload(monthKey: "2027-01", threshold: threshold)
            #expect(BudgetNotificationPayload(requestID: payload.requestID) == payload)
            #expect(BudgetNotificationPayload(userInfo: payload.userInfo) == payload)
        }
    }

    @Test func otherIDsAndPayloadsAreNotBudgetAlerts() {
        for id in ["budget-2026-11-50", "budget-2026-13-80", "budget-26-11-80", "other-2026-11-80", "budget-2026-11", ""] {
            #expect(BudgetNotificationPayload(requestID: id) == nil, "\(id)")
        }
        #expect(BudgetNotificationPayload(userInfo: [:]) == nil)
        #expect(BudgetNotificationPayload(userInfo: ["route": "other", "month": "2026-11", "threshold": "80"]) == nil)
        #expect(BudgetNotificationPayload(userInfo: ["route": "budget", "month": "2026-11", "threshold": 80]) == nil)
    }
}

@Suite struct SystemNotificationCenterTests {
    @Test func authorizationMapping() {
        #expect(SystemNotificationCenter.authorization(for: .notDetermined) == .notDetermined)
        #expect(SystemNotificationCenter.authorization(for: .authorized) == .allowed)
        #expect(SystemNotificationCenter.authorization(for: .provisional) == .allowed)
        #if os(iOS)
        #expect(SystemNotificationCenter.authorization(for: .ephemeral) == .allowed)
        #endif
        #expect(SystemNotificationCenter.authorization(for: .denied) == .denied)
    }

    @Test func systemRequestIsImmediateWithStableIDAndPayload() {
        let request = BudgetNotificationRequest(
            payload: BudgetNotificationPayload(monthKey: "2026-11", threshold: .hundred),
            title: "Budget used up", body: "Tap to see your budget."
        )
        let system = SystemNotificationCenter.systemRequest(for: request)
        #expect(system.identifier == "budget-2026-11-100")
        #expect(system.trigger == nil, "shown now, not scheduled")
        #expect(system.content.title == "Budget used up")
        #expect(system.content.body == "Tap to see your budget.")
        #expect(BudgetNotificationPayload(userInfo: system.content.userInfo) == request.payload)
    }

    @Test func budgetAlertsShowNoSystemBannerInTheForeground() {
        let budget = BudgetNotificationPayload(monthKey: "2026-11", threshold: .eighty).userInfo
        #expect(BudgetNotificationDelegate.presentationOptions(for: budget).isEmpty)
        #expect(BudgetNotificationDelegate.presentationOptions(for: [:]) == [.banner, .list, .sound])
    }
}
