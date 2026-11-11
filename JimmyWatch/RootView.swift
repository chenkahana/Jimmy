import SwiftUI

/// Root of the watch app: Now Playing, Queue and Recent in a vertically-paged `TabView` once the
/// phone has ever sent a state; before that, while the phone also isn't reachable, a single
/// "Open Jimmy on your iPhone" screen instead.
struct RootView: View {
    @Environment(WatchSessionClient.self) private var client

    var body: some View {
        if client.state == nil && !client.isReachable {
            NotReachableView()
        } else {
            TabView {
                NowPlayingView()
                QueueView()
                RecentView()
            }
            .tabViewStyle(.verticalPage)
        }
    }
}
