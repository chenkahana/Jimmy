import SwiftUI

/// The last episodes played on the phone. Tapping an episode plays it again.
struct RecentView: View {
    @Environment(WatchSessionClient.self) private var client

    var body: some View {
        let recent = client.state?.recent ?? []
        if recent.isEmpty {
            ContentUnavailableView("No Recent Episodes", systemImage: "clock")
        } else {
            List {
                ForEach(recent) { episode in
                    EpisodeRow(episode: episode)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            client.send(.playEpisode(episode.id))
                        }
                }
            }
        }
    }
}
