import Foundation

/// Temporary PodcastStore stub for build compatibility
class PodcastStore {
    static let shared = PodcastStore()
    
    private init() {}
    
    func batchWrite(_ episodesByPodcast: [UUID: [Episode]]) async {
        // Stub implementation
    }
} 