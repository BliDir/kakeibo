import CoreGraphics
import Foundation
import KakeiboCore
import Testing
@testable import KakeiboStore

@MainActor
@Suite struct AppSettingsTests {
    let suiteName = "SettingsTests-\(UUID().uuidString)"

    private func defaults() -> UserDefaults { UserDefaults(suiteName: suiteName)! }

    @Test func defaultPaymentStartsAsCash() {
        #expect(AppSettings(defaults: defaults()).defaultPayment == .cash)
    }

    @Test func defaultPaymentIsRemembered() {
        let store = defaults()
        defer { store.removePersistentDomain(forName: suiteName) }
        AppSettings(defaults: store).defaultPayment = .icCard
        #expect(AppSettings(defaults: store).defaultPayment == .icCard)
        #expect(store.string(forKey: AppSettings.defaultPaymentKey) == "icCard")
    }

    @Test func unknownStoredValueFallsBackToCash() {
        let store = defaults()
        defer { store.removePersistentDomain(forName: suiteName) }
        store.set("bitcoin", forKey: AppSettings.defaultPaymentKey)
        #expect(AppSettings(defaults: store).defaultPayment == .cash)
    }

    @Test func manualEntryStartsWithTheDefaultPayment() {
        let form = ReviewForm(manualOn: Date(timeIntervalSince1970: 1_793_674_800), payment: .qrPay)
        #expect(form.draft.payment == .qrPay)
        #expect(!form.hasUnsavedChanges, "the default is not an edit")
        #expect(ReviewForm(manualOn: .now).draft.payment == .cash)
    }
}

@MainActor
@Suite struct SettingsModelTests {
    @Test func versionAndBuild() {
        #expect(SettingsModel.versionText(info: ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "7"]) == "1.0 (7)")
        #expect(SettingsModel.versionText(info: ["CFBundleShortVersionString": "1.0"]) == "1.0")
        #expect(SettingsModel.versionText(info: [:]) == "?")
    }

    @Test func photoUsageCountsFilesAndBytes() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SettingsPhotos-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let photos = try PhotoStore(directory: folder)
        let model = SettingsModel(settings: AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!),
                                  photoStore: photos, info: [:])
        await model.refreshPhotoUsage()
        #expect(model.photoUsage == .none)

        try photos.save(image: Self.image())
        try photos.save(image: Self.image())
        await model.refreshPhotoUsage()
        #expect(model.photoUsage.count == 2)
        #expect(model.photoUsage.bytes == (try photos.totalBytes()))
        #expect(model.photoUsage.bytes > 0)
        #expect(!model.photoUsageFailed)
    }

    @Test func noPhotoStoreMeansNoUsage() async {
        let model = SettingsModel(settings: AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!),
                                  photoStore: nil, info: [:])
        await model.refreshPhotoUsage()
        #expect(model.photoUsage == .none)
    }

    private static func image() -> CGImage {
        let context = CGContext(data: nil, width: 40, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        return context.makeImage()!
    }
}
