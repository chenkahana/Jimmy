import Foundation
import OSLog
import Combine
import SwiftUI

/// 🎯 Progressive Podcast Sorter - Maintains sort order during progressive loading
/// Ensures shows appear in correct order as they stream in, not just appended
@MainActor
final class ProgressivePodcastSorter: ObservableObject {
    private let logger = Logger(subsystem: "Jimmy.ProgressiveSorter", category: "Sorting")
    
    // MARK: - Initialization
    
    init() {
        // Restore cached sorting state on app launch for instant loading
        Task {
            await restoreFromCache()
        }
    }
    
    // MARK: - Sorting Configuration
    enum SortMode {
        case latestEpisode    // Default: Sort by newest episode date
        case alphabetical     // Sort by podcast title A-Z
        case subscriptionDate // Sort by when user subscribed
        case author          // Sort by author name
        
        var displayName: String {
            switch self {
            case .latestEpisode: return "Latest Episode"
            case .alphabetical: return "Alphabetical"
            case .subscriptionDate: return "Recently Added"
            case .author: return "Author"
            }
        }
    }
    
    // MARK: - Internal State
    @Published private(set) var sortedPodcasts: [Podcast] = []
    private(set) var currentSortMode: SortMode = .latestEpisode
    private var episodeCache: [UUID: [Episode]] = [:]
    
    // MARK: - Persistent Cache Keys
    private static let sortedPodcastsCacheKey = "progressive_sorted_podcasts"
    private static let sortModeCacheKey = "progressive_sort_mode"
    private static let episodeCacheCacheKey = "progressive_episode_cache"
    
    // MARK: - Public API
    
    /// Add a podcast while maintaining sort order
    func addPodcast(_ podcast: Podcast, episodes: [Episode] = []) {
        // Cache episodes for this podcast
        if !episodes.isEmpty {
            episodeCache[podcast.id] = episodes
        }
        
        // Check if podcast already exists
        if sortedPodcasts.contains(where: { $0.id == podcast.id }) {
            return
        }
        
        // Find correct insertion point to maintain sort order
        let insertionIndex = findInsertionIndex(for: podcast)
        
        // Insert at correct position
        sortedPodcasts.insert(podcast, at: insertionIndex)
        
        // Persist the updated sorted order
        Task {
            await saveToCache()
        }
    }
    
    /// Get current sorted podcasts array
    func getSortedPodcasts() -> [Podcast] {
        return sortedPodcasts
    }
    
    /// Clear all podcasts (for refresh)
    func clear() {
        sortedPodcasts.removeAll()
        episodeCache.removeAll()

        
        // Clear persistent cache
        Task {
            await clearCache()
        }
    }
    
    /// Change sort mode and re-sort existing podcasts
    func setSortMode(_ mode: SortMode) {
        guard mode != currentSortMode else { return }
        
        currentSortMode = mode
        
        // Re-sort existing podcasts with new mode
        sortedPodcasts.sort { podcast1, podcast2 in
            comparepodcasts(podcast1, podcast2, mode: mode)
        }
        
        // Persist the new sort mode and order
        Task {
            await saveToCache()
        }
    }
    
    /// Update episodes for a podcast and re-sort if needed
    func updateEpisodes(for podcastId: UUID, episodes: [Episode]) {
        episodeCache[podcastId] = episodes
        
        // If sorting by latest episode, we might need to re-sort
        if currentSortMode == .latestEpisode {
            sortedPodcasts.sort { podcast1, podcast2 in
                comparepodcasts(podcast1, podcast2, mode: .latestEpisode)
            }
        }
    }
    
    /// Remove a podcast
    func removePodcast(withId id: UUID) {
        sortedPodcasts.removeAll { $0.id == id }
        episodeCache.removeValue(forKey: id)
    }
    
    // MARK: - Smart Insertion Logic
    
    private func findInsertionIndex(for newPodcast: Podcast) -> Int {
        // Binary search for optimal insertion point
        var left = 0
        var right = sortedPodcasts.count
        
        while left < right {
            let mid = (left + right) / 2
            let comparison = comparepodcasts(newPodcast, sortedPodcasts[mid], mode: currentSortMode)
            
            if comparison {
                // newPodcast should come before mid
                right = mid
            } else {
                // newPodcast should come after mid
                left = mid + 1
            }
        }
        
        return left
    }
    
    // MARK: - Comparison Logic
    
    private func comparepodcasts(_ podcast1: Podcast, _ podcast2: Podcast, mode: SortMode) -> Bool {
        switch mode {
        case .latestEpisode:
            return compareByLatestEpisode(podcast1, podcast2)
            
        case .alphabetical:
            return podcast1.title.localizedCaseInsensitiveCompare(podcast2.title) == .orderedAscending
            
        case .subscriptionDate:
            // Fallback to creation date or alphabetical if no subscription date
            let date1 = podcast1.lastEpisodeDate ?? Date.distantPast
            let date2 = podcast2.lastEpisodeDate ?? Date.distantPast
            return date1 > date2 // Newer subscriptions first
            
        case .author:
            let author1 = podcast1.author.isEmpty ? "Unknown" : podcast1.author
            let author2 = podcast2.author.isEmpty ? "Unknown" : podcast2.author
            return author1.localizedCaseInsensitiveCompare(author2) == .orderedAscending
        }
    }
    
    private func compareByLatestEpisode(_ podcast1: Podcast, _ podcast2: Podcast) -> Bool {
        // First check cached episodes
        let episodes1 = episodeCache[podcast1.id] ?? []
        let episodes2 = episodeCache[podcast2.id] ?? []
        
        let latestDate1: Date
        let latestDate2: Date
        
        if !episodes1.isEmpty {
            latestDate1 = episodes1.compactMap { $0.publishedDate }.max() ?? Date.distantPast
        } else {
            // Fallback to podcast's last episode date
            latestDate1 = podcast1.lastEpisodeDate ?? Date.distantPast
        }
        
        if !episodes2.isEmpty {
            latestDate2 = episodes2.compactMap { $0.publishedDate }.max() ?? Date.distantPast
        } else {
            latestDate2 = podcast2.lastEpisodeDate ?? Date.distantPast
        }
        
        // Primary sort: newer episodes first
        if abs(latestDate1.timeIntervalSince(latestDate2)) > 1 { // More than 1 second difference
            return latestDate1 > latestDate2
        }
        
        // Secondary sort: alphabetical for stability
        return podcast1.title.localizedCaseInsensitiveCompare(podcast2.title) == .orderedAscending
    }
    
    // MARK: - Performance Monitoring
    
    func getPerformanceStats() -> (totalPodcasts: Int, sortMode: String) {
        return (
            totalPodcasts: sortedPodcasts.count,
            sortMode: currentSortMode.displayName
        )
    }
}

// MARK: - Integration with LibraryViewModel

extension ProgressivePodcastSorter {
    /// Batch add podcasts efficiently (for initial load)
    func addPodcasts(_ podcasts: [Podcast], episodeMap: [UUID: [Episode]] = [:]) {
        let startTime = Date()
        
        // Add episodes to cache
        for (podcastId, episodes) in episodeMap {
            episodeCache[podcastId] = episodes
        }
        
        // Add all podcasts and then sort once (more efficient than inserting one by one)
        // Add new podcasts ensuring no duplicates
        for podcast in podcasts {
            if !sortedPodcasts.contains(where: { $0.id == podcast.id }) {
                sortedPodcasts.append(podcast)
            }
        }
        sortedPodcasts.sort { podcast1, podcast2 in
            comparepodcasts(podcast1, podcast2, mode: currentSortMode)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Persist the batch changes
        Task {
            await saveToCache()
        }
    }
}

// MARK: - Persistent Cache Implementation

extension ProgressivePodcastSorter {
    
    /// Save current state to persistent cache for instant app reopening
    private func saveToCache() async {
        do {
            // Save sorted podcasts
            let podcastsData = try JSONEncoder().encode(sortedPodcasts)
            UserDefaults.standard.set(podcastsData, forKey: Self.sortedPodcastsCacheKey)
            
            // Save sort mode
            UserDefaults.standard.set(currentSortMode.rawValue, forKey: Self.sortModeCacheKey)
            
            // Save episode cache (IDs only for performance)
            let episodeCacheData = episodeCache.mapValues { episodes in
                episodes.map { $0.id }
            }
            let cacheData = try JSONEncoder().encode(episodeCacheData)
            UserDefaults.standard.set(cacheData, forKey: Self.episodeCacheCacheKey)
            

            
        } catch {
            logger.error("❌ Failed to save sorting cache: \(error.localizedDescription)")
        }
    }
    
    /// Restore state from persistent cache for instant app loading
    private func restoreFromCache() async {
        do {
            // Restore sort mode first
            if let sortModeString = UserDefaults.standard.string(forKey: Self.sortModeCacheKey),
               let mode = SortMode.fromRawValue(sortModeString) {
                currentSortMode = mode
            }
            
            // Restore sorted podcasts
            if let podcastsData = UserDefaults.standard.data(forKey: Self.sortedPodcastsCacheKey) {
                let cachedPodcasts = try JSONDecoder().decode([Podcast].self, from: podcastsData)
                sortedPodcasts = cachedPodcasts
            }
            
            // Restore episode cache (we'll get full episodes from other caches)
            if let cacheData = UserDefaults.standard.data(forKey: Self.episodeCacheCacheKey) {
                let episodeCacheIds = try JSONDecoder().decode([UUID: [UUID]].self, from: cacheData)
                // Note: Full episodes will be loaded from IntelligentCacheEngine when needed
            }
            
        } catch {
            logger.error("❌ Failed to restore sorting cache: \(error.localizedDescription)")
            // Start fresh if cache is corrupted
            currentSortMode = .latestEpisode
            sortedPodcasts = []
            episodeCache = [:]
        }
    }
    
    /// Clear all persistent cache
    private func clearCache() async {
        UserDefaults.standard.removeObject(forKey: Self.sortedPodcastsCacheKey)
        UserDefaults.standard.removeObject(forKey: Self.sortModeCacheKey)
        UserDefaults.standard.removeObject(forKey: Self.episodeCacheCacheKey)

    }
    
    /// Check if we have valid cached data for instant loading
    func hasCachedData() -> Bool {
        return UserDefaults.standard.data(forKey: Self.sortedPodcastsCacheKey) != nil
    }
    
    /// Force restore from cache (for manual testing)
    func forceRestoreFromCache() async {
        await restoreFromCache()
    }
}

// MARK: - SortMode Extensions

extension ProgressivePodcastSorter.SortMode {
    var rawValue: String {
        switch self {
        case .latestEpisode: return "latestEpisode"
        case .alphabetical: return "alphabetical"
        case .subscriptionDate: return "subscriptionDate"
        case .author: return "author"
        }
    }
    
    static func fromRawValue(_ rawValue: String) -> Self? {
        switch rawValue {
        case "latestEpisode": return .latestEpisode
        case "alphabetical": return .alphabetical
        case "subscriptionDate": return .subscriptionDate
        case "author": return .author
        default: return nil
        }
    }
}
