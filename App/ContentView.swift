import SwiftUI

/// Placeholder root screen. Replaced by the Ledger screen in a later ticket.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "ledger.empty.title",
                systemImage: "doc.text.viewfinder",
                description: Text("ledger.empty.message")
            )
            .navigationTitle("app.title")
        }
    }
}

#Preview {
    ContentView()
}
