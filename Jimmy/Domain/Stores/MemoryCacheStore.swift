import Foundation
import UIKit

/// A hashable key for caching episode pages, identified by podcast ID and page number.
struct EpisodePageKey: Hashable {
    let podcastID: UUID
    let page: Int
}

/// A centralized, shared store for in-memory caches.
/// This singleton provides global access to various application-wide caches,
/// helping to reduce redundant data fetching and improve performance.
/// 
/// CRITICAL MEMORY FIX: Reduced all cache limits to prevent excessive memory usage
final class MemoryCacheStore {
    /// The shared singleton instance of the cache store.
    static let shared = MemoryCacheStore()

    // MARK: - Dedicated Caches (REDUCED LIMITS FOR MEMORY OPTIMIZATION)

    /// Caches `Podcast` objects, keyed by their `UUID`.
    /// REDUCED: countLimit from 100 to 50 to prevent memory bloat
    let subscriptionCache = MemoryCache<UUID, Podcast>(name: "SubscriptionCache", countLimit: 50)

    /// Caches `PodcastMetadata` objects, keyed by the podcast's feed `URL`.
    /// REDUCED: countLimit from 200 to 100 as metadata can still be substantial
    let showCache = MemoryCache<URL, ShowMetadata>(name: "ShowCache", countLimit: 100)

    /// Caches pages of `Episode` arrays, keyed by `EpisodePageKey`.
    /// CRITICAL FIX: Reduced totalCostLimit from 5000 to 1000 (80% reduction)
    /// This prevents massive episode data accumulation in memory
    let episodePageCache = MemoryCache<EpisodePageKey, [Episode]>(name: "EpisodePageCache", totalCostLimit: 1000) // Approx 10 pages of 100 episodes

    /// Caches detailed `Episode` objects, keyed by their `UUID`.
    /// REDUCED: countLimit from 500 to 200 to prevent memory bloat
    let episodeDetailCache = MemoryCache<UUID, Episode>(name: "EpisodeDetailCache", countLimit: 200)

    /// Caches `PlaybackState` objects, keyed by their corresponding `Episode`'s `UUID`.
    /// REDUCED: countLimit from 1000 to 500 - playback states are lightweight but still need limits
    let playbackStateCache = MemoryCache<UUID, PlaybackState>(name: "PlaybackStateCache", countLimit: 500)
    
    private init() {
        // Private initializer to enforce singleton pattern.
        setupEvictionLogging()
        setupMemoryPressureHandling()
    }
    
    // MARK: - Cache Management

    /// Clears all caches managed by this store.
    /// This can be used during logout, significant data resets, or for debugging.
    func clearAllCaches() {
        subscriptionCache.removeAllValues()
        showCache.removeAllValues()
        episodePageCache.removeAllValues()
        episodeDetailCache.removeAllValues()
        playbackStateCache.removeAllValues()
    }
    
    /// Emergency cache cleanup when memory pressure is detected
    func performEmergencyCleanup() {
        // Clear the largest caches first
        episodePageCache.removeAllValues()
        episodeDetailCache.removeAllValues()
        
        // Keep only essential caches with reduced size
        // This is handled automatically by NSCache when memory pressure occurs
    }
    
    /// Invalidates a specific key in a given cache.
    func invalidate<Key: Hashable, Value>(key: Key, in cache: MemoryCache<Key, Value>) {
        cache.removeValue(forKey: key)
    }
    
    /// Logs cache evictions for debugging memory pressure issues.
    private func setupEvictionLogging() {
        // Example of setting up an eviction handler for one of the caches
        episodeDetailCache.onObjectEvicted = { episode in
            // No print statement here
        }
        
        episodePageCache.onObjectEvicted = { episodes in
            // No print statement here
        }
    }
    
    /// Setup memory pressure handling
    private func setupMemoryPressureHandling() {
        // Listen for memory warnings and proactively clean up
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.performEmergencyCleanup()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Helper Methods for Repository Layer
    
    /// Removes all episode page cache entries for a specific podcast
    func clearEpisodePages(for podcastID: UUID) {
        // Since we can't iterate over cache keys directly, we'll clear pages 1-10
        // This covers most realistic pagination scenarios
        for page in 1...10 {
            let pageKey = EpisodePageKey(podcastID: podcastID, page: page)
            episodePageCache.removeValue(forKey: pageKey)
        }
    }
    
    /// Checks if any episode page cache exists for a specific podcast
    func hasEpisodePages(for podcastID: UUID) -> Bool {
        // Check first few pages to see if any data exists
        for page in 1...3 {
            let pageKey = EpisodePageKey(podcastID: podcastID, page: page)
            if episodePageCache.value(forKey: pageKey) != nil {
                return true
            }
        }
        return false
    }
} 