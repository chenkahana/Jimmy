import SwiftUI

@main
struct JimmyWatchApp: App {
    @State private var client = WatchSessionClient()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(client)
        }
    }
}
