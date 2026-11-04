import SwiftUI

@main
struct KakeiboApp: App {
    @State private var services = AppServices.make()

    var body: some Scene {
        WindowGroup {
            ContentView(services: services)
                .task { services.cleanUp() }
        }
    }
}
