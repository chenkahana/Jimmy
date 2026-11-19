import SwiftUI

/// The phone's queue. Tapping an episode plays it; swiping removes it.
struct QueueView: View {
    @Environment(WatchSessionClient.self) private var client

    var body: some View {
        let queue = client.state?.queue ?? []
        if queue.isEmpty {
            ContentUnavailableView("Queue Is Empty", systemImage: "list.bullet")
        } else {
            List {
                ForEach(queue) { episode in
                    // A button, not a tap gesture, so VoiceOver announces each row as one.
                    Button {
                        client.send(.playEpisode(episode.id))
                    } label: {
                        EpisodeRow(episode: episode)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            client.send(.removeFromQueue(episode.id))
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}
