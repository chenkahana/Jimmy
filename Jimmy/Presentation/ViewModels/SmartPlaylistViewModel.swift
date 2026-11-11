import Foundation
import os

@MainActor
class SmartPlaylistViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "SmartPlaylistViewModel")
    @Published var episodes: [EpisodeWithPlaybackState] = []
    @Published var isLoading = false

    let playlistType: SmartPlaylistType
    private let service = SmartPlaylistService.shared

    init(playlistType: SmartPlaylistType) {
        self.playlistType = playlistType
        Task { await loadEpisodes() }
    }

    func loadEpisodes() async {
        isLoading = true
        do {
            episodes = try await service.fetchEpisodes(for: playlistType)
        } catch {
            Self.logger.error("Failed to load smart playlist: \(error)")
        }
        isLoading = false
    }
}
