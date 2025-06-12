import Foundation

/// PodcastDataManager handles podcast data management and background refresh
class PodcastDataManager {
    static let shared = PodcastDataManager()
    
    var podcasts: [Podcast] {
        return PodcastService.shared.loadPodcasts()
    }
    
    private init() {}
    
    func performBackgroundRefresh() async -> Bool {
        do {
            // Refresh episodes for all podcasts
            let podcasts = PodcastService.shared.loadPodcasts()
            
            if podcasts.isEmpty {
                return true
            }
            
            // Use OptimizedPodcastService for batch fetching
            return await withCheckedContinuation { continuation in
                OptimizedPodcastService.shared.batchFetchEpisodes(for: podcasts) { episodesByPodcast in
                    let totalEpisodes = episodesByPodcast.values.reduce(0) { $0 + $1.count }
                    continuation.resume(returning: true)
                }
            }
        } catch {
            return false
        }
    }
    
    func loadPodcasts() {
        let podcasts = PodcastService.shared.loadPodcasts()
    }
} 