import Foundation
import OSLog

/// Swift Actor for thread-safe podcast storage following CHAT_HELP.md specification
actor PodcastStore {
    static let shared = PodcastStore()
    
    // MARK: - Private Properties
    private let repository = PodcastRepository.shared
    private var episodeCache: [UUID: [Episode]] = [:]
    private var lastUpdateTimes: [UUID: Date] = [:]
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "Jimmy", category: "PodcastStore")
    #endif
    
    private init() {}
    
    // MARK: - Read Operations (Thread-Safe)
    
    /// Read all episodes (thread-safe)
    func readAll() async -> [Episode] {
        #if canImport(OSLog)
        logger.info("📖 Reading all episodes from store")
        #endif
        
        return await repository.fetchCachedEpisodes()
    }
    
    /// Read episodes for specific podcast (thread-safe)
    func readEpisodes(for podcastID: UUID) async -> [Episode] {
        #if canImport(OSLog)
        logger.debug("📖 Reading episodes for podcast: \(podcastID)")
        #endif
        
        // Check cache first
        if let cachedEpisodes = episodeCache[podcastID],
           let lastUpdate = lastUpdateTimes[podcastID],
           Date().timeIntervalSince(lastUpdate) < 300 { // 5 minute cache
            #if canImport(OSLog)
            logger.debug("💾 Returning cached episodes for podcast: \(podcastID)")
            #endif
            return cachedEpisodes
        }
        
        // Fetch from repository
        let episodes = await repository.getEpisodes(for: podcastID)
        
        // Update cache
        episodeCache[podcastID] = episodes
        lastUpdateTimes[podcastID] = Date()
        
        return episodes
    }
    
    /// Get cache statistics
    func getCacheStats() -> (cachedPodcasts: Int, totalEpisodes: Int, lastUpdate: Date?) {
        let totalEpisodes = episodeCache.values.reduce(0) { $0 + $1.count }
        let lastUpdate = lastUpdateTimes.values.max()
        
        return (
            cachedPodcasts: episodeCache.count,
            totalEpisodes: totalEpisodes,
            lastUpdate: lastUpdate
        )
    }
    
    // MARK: - Write Operations (Thread-Safe)
    
    /// Write episode changes (thread-safe)
    func write(_ changes: EpisodeChanges) async {
        #if canImport(OSLog)
        logger.info("✍️ Writing changes: \(changes.inserted.count) inserted, \(changes.updated.count) updated, \(changes.deleted.count) deleted")
        #endif
        
        await repository.applyChanges(changes)
        
        // Update cache for affected podcasts (handle optional podcastID)
        let insertedPodcastIDs = changes.inserted.compactMap(\.podcastID)
        let updatedPodcastIDs = changes.updated.compactMap(\.podcastID)
        let affectedPodcasts = Set(insertedPodcastIDs + updatedPodcastIDs)
        
        for podcastID in affectedPodcasts {
            episodeCache.removeValue(forKey: podcastID)
            lastUpdateTimes.removeValue(forKey: podcastID)
        }
        
        #if canImport(OSLog)
        logger.debug("🗑️ Invalidated cache for \(affectedPodcasts.count) podcasts")
        #endif
    }
    
    /// Batch write episodes for multiple podcasts
    func batchWrite(_ episodesByPodcast: [UUID: [Episode]]) async {
        #if canImport(OSLog)
        logger.info("📦 Batch writing episodes for \(episodesByPodcast.count) podcasts")
        #endif
        
        let startTime = Date()
        
        for (podcastID, newEpisodes) in episodesByPodcast {
            let currentEpisodes = await repository.getEpisodes(for: podcastID)
            let changes = computeDiff(current: currentEpisodes, new: newEpisodes)
            
            if !changes.isEmpty {
                await repository.applyChanges(changes)
                
                // Invalidate cache for this podcast
                episodeCache.removeValue(forKey: podcastID)
                lastUpdateTimes.removeValue(forKey: podcastID)
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let totalEpisodes = episodesByPodcast.values.reduce(0) { $0 + $1.count }
        
        #if canImport(OSLog)
        logger.info("✅ Batch write completed: \(totalEpisodes) episodes in \(String(format: "%.3f", duration))s")
        #endif
    }
    
    /// Clear cache for specific podcast
    func clearCache(for podcastID: UUID) {
        episodeCache.removeValue(forKey: podcastID)
        lastUpdateTimes.removeValue(forKey: podcastID)
        
        #if canImport(OSLog)
        logger.debug("🗑️ Cleared cache for podcast: \(podcastID)")
        #endif
    }
    
    /// Clear all caches
    func clearAllCaches() {
        episodeCache.removeAll()
        lastUpdateTimes.removeAll()
        
        #if canImport(OSLog)
        logger.info("🗑️ Cleared all caches")
        #endif
    }
    
    // MARK: - Private Helpers
    
    private func computeDiff(current: [Episode], new: [Episode]) -> EpisodeChanges {
        let currentDict = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let newDict = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        
        let inserted = new.filter { currentDict[$0.id] == nil }
        let deleted = current.compactMap { currentDict[$0.id] != nil && newDict[$0.id] == nil ? $0.id : nil }
        let updated = new.filter { episode in
            if let currentEpisode = currentDict[episode.id] {
                return !episode.isEqual(to: currentEpisode)
            }
            return false
        }
        
        return EpisodeChanges(inserted: inserted, updated: updated, deleted: deleted)
    }
}

// MARK: - Store Extensions

extension PodcastStore {
    /// Convenience method to get episodes with automatic refresh
    func getEpisodesWithRefresh(for podcastID: UUID, using fetchWorker: FetchWorker, podcast: Podcast) async -> [Episode] {
        let episodes = await readEpisodes(for: podcastID)
        
        // Trigger background refresh if needed
        if needsRefresh(for: podcastID) {
            Task.detached(priority: .background) {
                let freshEpisodesDict = await fetchWorker.batchFetchEpisodes(for: [podcast])
                if let freshEpisodes = freshEpisodesDict[podcastID] {
                    await self.updateEpisodes(freshEpisodes, for: podcastID)
                }
            }
        }
        
        return episodes
    }
    
    /// Check if podcast needs refresh (private helper)
    private func needsRefresh(for podcastID: UUID) -> Bool {
        guard let lastUpdate = lastUpdateTimes[podcastID] else {
            return true // Never updated, needs refresh
        }
        
        // Refresh if older than 30 minutes
        return Date().timeIntervalSince(lastUpdate) > 1800
    }
    
    /// Update episodes for a specific podcast
    private func updateEpisodes(_ episodes: [Episode], for podcastID: UUID) async {
        let currentEpisodes = await repository.getEpisodes(for: podcastID)
        let changes = computeDiff(current: currentEpisodes, new: episodes)
        
        if !changes.isEmpty {
            await write(changes)
            
            #if canImport(OSLog)
            logger.info("🔄 Updated \(changes.inserted.count + changes.updated.count) episodes for podcast: \(podcastID)")
            #endif
        }
    }
} 