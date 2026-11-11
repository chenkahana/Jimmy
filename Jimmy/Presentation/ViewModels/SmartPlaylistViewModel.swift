import Foundation
import JimmyKit

@MainActor
class SmartPlaylistViewModel: ObservableObject {
    @Published var episodes: [EpisodeWithPlaybackState] = []
    @Published var isLoading = false

    let playlistType: SmartPlaylistType

    init(playlistType: SmartPlaylistType) {
        self.playlistType = playlistType
        Task { await loadEpisodes() }
    }

    func loadEpisodes() async {
        isLoading = true
        let items = await AppModel.current?.episodes(for: playlistType.rule) ?? []
        episodes = items.map { $0.asLegacyEpisodeWithPlaybackState() }
        isLoading = false
    }
}
