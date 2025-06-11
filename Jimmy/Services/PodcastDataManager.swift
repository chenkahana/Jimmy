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
                print("📚 PodcastDataManager: No podcasts to refresh")
                return true
            }
            
            print("📚 PodcastDataManager: Starting background refresh for \(podcasts.count) podcasts")
            
            // Use OptimizedPodcastService for batch fetching
            return await withCheckedContinuation { continuation in
                OptimizedPodcastService.shared.batchFetchEpisodes(for: podcasts) { episodesByPodcast in
                    let totalEpisodes = episodesByPodcast.values.reduce(0) { $0 + $1.count }
                    print("📚 PodcastDataManager: Background refresh completed - fetched \(totalEpisodes) episodes")
                    continuation.resume(returning: true)
                }
            }
        } catch {
            print("❌ PodcastDataManager: Background refresh failed: \(error.localizedDescription)")
            return false
        }
    }
    
    func loadPodcasts() {
        let podcasts = PodcastService.shared.loadPodcasts()
        print("📚 PodcastDataManager: Loaded \(podcasts.count) podcasts")
    }
} 