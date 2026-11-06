import Foundation
import KakeiboCore
import Observation

/// The few preferences v1.0 has, kept in `UserDefaults`.
///
/// App language is not stored here: iOS keeps it per app (Settings › Kakeibo › Language),
/// and the app follows the system until the user changes it there.
@MainActor
@Observable
public final class AppSettings {
    static let defaultPaymentKey = "defaultPayment"

    private let defaults: UserDefaults

    /// Payment method a new manual entry starts with. Cash until changed.
    public var defaultPayment: PaymentMethod {
        didSet { defaults.set(defaultPayment.rawValue, forKey: Self.defaultPaymentKey) }
    }

    static let budgetAlertsEnabledKey = "budgetAlertsEnabled"

    /// The user turned budget alerts (80% and 100%) on in Settings. Off until they do;
    /// whether iOS allows notifications is separate (`BudgetNotifier.authorization`).
    public var budgetAlertsEnabled: Bool {
        didSet { defaults.set(budgetAlertsEnabled, forKey: Self.budgetAlertsEnabledKey) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultPayment = defaults.string(forKey: Self.defaultPaymentKey).flatMap(PaymentMethod.init(rawValue:)) ?? .cash
        budgetAlertsEnabled = defaults.bool(forKey: Self.budgetAlertsEnabledKey)
    }
}

/// What the Settings screen reports: photo storage and the app version.
@MainActor
@Observable
public final class SettingsModel {
    /// Receipt photos on this iPhone and the space they take.
    public struct PhotoUsage: Equatable, Sendable {
        public var count: Int
        public var bytes: Int64

        public static let none = PhotoUsage(count: 0, bytes: 0)
    }

    public let settings: AppSettings
    private let photoStore: PhotoStore?
    private let info: [String: Any]

    public private(set) var photoUsage: PhotoUsage = .none
    /// Set when the photo folder could not be read.
    public private(set) var photoUsageFailed = false

    /// - Parameter info: the app's Info.plist (`Bundle.main.infoDictionary`).
    public init(settings: AppSettings, photoStore: PhotoStore?, info: [String: Any]) {
        self.settings = settings
        self.photoStore = photoStore
        self.info = info
    }

    /// "1.0 (1)": the marketing version and the build number.
    public var versionText: String {
        Self.versionText(info: info)
    }

    static func versionText(info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        guard let build = info["CFBundleVersion"] as? String, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }

    /// Reads the photo folder off the main thread.
    public func refreshPhotoUsage() async {
        guard let photoStore else {
            photoUsage = .none
            return
        }
        let result = await Task.detached(priority: .utility) { () -> PhotoUsage? in
            guard let names = try? photoStore.storedNames(), let bytes = try? photoStore.totalBytes() else { return nil }
            return PhotoUsage(count: names.count, bytes: bytes)
        }.value
        photoUsage = result ?? .none
        photoUsageFailed = result == nil
    }
}
