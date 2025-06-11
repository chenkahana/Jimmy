import Foundation
import SwiftUI

/// Temporary UnifiedEpisodeController stub for build compatibility
@MainActor
class UnifiedEpisodeController: ObservableObject {
    static let shared = UnifiedEpisodeController()
    
    @Published var episodes: [Episode] = []
    
    private init() {}
    
    func isEpisodePlayed(_ episodeId: UUID) -> Bool {
        return false
    }
    
    func getEpisode(by id: UUID) -> Episode? {
        return nil
    }
    
    func getAllEpisodes() async -> [Episode] {
        return episodes
    }
    
    func markEpisodeAsPlayed(_ episode: Episode, played: Bool) {
        print("▶️ UnifiedEpisodeController: Marking episode '\(episode.title)' as played: \(played)")
        // Stub implementation
    }
    
    func markAllEpisodesAsPlayed(for podcastId: UUID) {
        print("▶️ UnifiedEpisodeController: Marking all episodes as played for podcast: \(podcastId)")
        // Stub implementation
    }
    
    func markAllEpisodesAsUnplayed(for podcastId: UUID) {
        print("▶️ UnifiedEpisodeController: Marking all episodes as unplayed for podcast: \(podcastId)")
        // Stub implementation
    }
} 