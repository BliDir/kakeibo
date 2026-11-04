import SwiftUI

@main
struct KakeiboApp: App {
    @State private var services = AppServices.make()

    var body: some Scene {
        WindowGroup {
            ContentView(services: services)
                .modelContainer(services.container)
                .task { services.cleanUp() }
        }
    }
}
