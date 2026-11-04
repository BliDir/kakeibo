import SwiftUI

@main
struct KakeiboApp: App {
    @State private var services = AppServices.make()

    var body: some Scene {
        WindowGroup {
            ContentView(services: services)
                .task { services.cleanUp() }
                .preferredColorScheme(Self.testColorScheme)
        }
    }

    /// Debug builds: `KAKEIBO_COLOR_SCHEME=dark` (or `light`) forces the appearance, so UI tests
    /// can audit and screenshot dark mode. Switching the simulator's appearance does not reach
    /// the app reliably in tests. Release builds always follow the system.
    private static var testColorScheme: ColorScheme? {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["KAKEIBO_COLOR_SCHEME"] {
        case "dark": .dark
        case "light": .light
        default: nil
        }
        #else
        nil
        #endif
    }
}
