import SwiftUI

/// Root tabs definitions
private let rootTabs: [(icon: String, title: String)] = [
    ("globe", "Discover"),
    ("list.bullet", "Queue"),
    ("play.circle", "Now Playing"),
    ("waveform", "Library"),
    ("gear", "Settings")
]

struct ContentView: View {
    @AppStorage("darkMode") private var darkMode = true
    @State private var selection = 0 // default Library will adjust after onAppear

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            TabView(selection: $selection) {
                DiscoverView().tag(0)
                QueueView().tag(1)
                CurrentPlayView().tag(2)
                LibraryView().tag(3)
                SettingsView().tag(4)
            }
            .onAppear { UITabBar.appearance().isHidden = true }
            .ignoresSafeArea(edges: .all)

            // Custom Liquid-Glass Tab Bar
            LiquidGlassTabBar(
                selectedIndex: $selection,
                tabs: rootTabs.enumerated().map { (idx, tuple) in 
                    TabItem(icon: tuple.icon, title: tuple.title, tag: idx)
                }
            )
        }
        .preferredColorScheme(darkMode ? .dark : .light)
    }
}

#Preview {
    ContentView()
} 