import Foundation
import SwiftUI
#if canImport(OSLog)
import OSLog
#endif

/// Service that manages caching of episodes for individual podcasts
class EpisodeCacheService: ObservableObject {
    static let shared = EpisodeCacheService()
    
    // MARK: - Cache Data Structures
    
    private struct CacheEntry {
        let episodes: [Episode]
        let timestamp: Date
        let lastModified: String? // ETags or Last-Modified headers for HTTP caching
        
        var isExpired: Bool {
            let expirationTime: TimeInterval = 30 * 60 // 30 minutes
            return Date().timeIntervalSince(timestamp) > expirationTime
        }
        
        var age: TimeInterval {
            return Date().timeIntervalSince(timestamp)
        }
    }
    
    // Codable structure for file storage
    private struct CacheData: Codable {
        let episodes: [Episode]
        let timestamp: TimeInterval
        let lastModified: String?
    }
    
    // Container for all cache entries
    private struct CacheContainer: Codable {
        let entries: [String: CacheData] // UUID string -> CacheData
    }
    
    private var episodeCache: [UUID: CacheEntry] = [:]
    private let cacheQueue = DispatchQueue(label: "episode-cache-queue", qos: .userInitiated, attributes: .concurrent)
    private let persistenceKey = "episodeCacheData"
    private let maxCacheEntries = 20 // Limit cache size to prevent memory issues
    private var isCacheLoaded = false
    private var cacheLoadingCompletions: [() -> Void] = []
#if canImport(OSLog)
    private let logger = Logger(subsystem: "com.jimmy.app", category: "cache")
#endif
    
    // MARK: - Published Properties
    
    @Published var isLoadingEpisodes: [UUID: Bool] = [:]
    @Published var loadingErrors: [UUID: String] = [:]
    
    // MARK: - Initialization
    
    private init() {
        // PERFORMANCE FIX: Load cache data asynchronously to prevent blocking initialization
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.loadCacheFromDisk()
            self?.startCacheCleanupTimer()
            self?.invalidateCacheOnFirstLaunchAfterFix()
        }
    }
    
    // MARK: - Public Interface
    
    /// Get episodes for a podcast, using cache when available
    /// - Parameters:
    ///   - podcast: The podcast to get episodes for
    ///   - forceRefresh: Whether to bypass cache and fetch fresh data
    ///   - completion: Completion handler with episodes
    func getEpisodes(
        for podcast: Podcast,
        forceRefresh: Bool = false,
        completion: @escaping ([Episode]) -> Void
    ) {
        // PERFORMANCE FIX: Ensure this doesn't block the main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let podcastID = podcast.id
            
            // Update loading state on main thread
            Task { @MainActor in
                self.isLoadingEpisodes[podcastID] = true
                self.loadingErrors[podcastID] = nil
            }
            
            // Check cache first (unless force refresh is requested) - use async access
            self.getCachedEpisodesAsync(for: podcastID, ignoreExpiry: true) { cachedEpisodes in
                // If we have cached episodes and not forcing refresh, return them immediately
                if let episodes = cachedEpisodes, !forceRefresh {
                    self.hasFreshCache(for: podcastID) { isFresh in
                        if isFresh {
                            #if canImport(OSLog)
                            self.logger.info("Using cached episodes for \(podcast.title, privacy: .public)")
                            #else
                            print("📱 Using cached episodes for \(podcast.title)")
                            #endif

                            Task { @MainActor in
                                self.isLoadingEpisodes[podcastID] = false
                                completion(episodes)
                            }
                            return
                        } else {
                            // Stale cache - show immediately then refresh in background
                            #if canImport(OSLog)
                            self.logger.info("Using stale episodes for \(podcast.title, privacy: .public) and refreshing")
                            #else
                            print("📱 Using stale episodes for \(podcast.title) and refreshing")
                            #endif

                            // Kick off a refresh before returning cached episodes
                            self.fetchAndCacheEpisodes(for: podcast) { _, _ in
                                Task { @MainActor in
                                    self.isLoadingEpisodes[podcastID] = false
                                }
                            }

                            // Return stale data immediately
                            Task { @MainActor in
                                completion(episodes)
                            }
                            return
                        }
                    }
                    return
                }
                
                // If offline, return cached data if available
                if !NetworkMonitor.shared.isConnected {
                    self.getCachedEpisodesAsync(for: podcastID, ignoreExpiry: true) { offlineCachedEpisodes in
                        if let episodes = offlineCachedEpisodes {
                            #if canImport(OSLog)
                            self.logger.info("Offline - using cached episodes for \(podcast.title, privacy: .public)")
                            #else
                            print("📡 Offline - using cached episodes for \(podcast.title)")
                            #endif
                            Task { @MainActor in
                                self.isLoadingEpisodes[podcastID] = false
                                self.loadingErrors[podcastID] = "You appear to be offline. Showing cached episodes."
                                completion(episodes)
                            }
                        } else {
                            Task { @MainActor in
                                self.isLoadingEpisodes[podcastID] = false
                                self.loadingErrors[podcastID] = "You appear to be offline."
                                completion([])
                            }
                        }
                    }
                    return
                }

                // Cache miss or expired - fetch fresh data
                #if canImport(OSLog)
                self.logger.info("Fetching fresh episodes for \(podcast.title, privacy: .public) (force: \(forceRefresh))")
                #else
                print("🌐 Fetching fresh episodes for \(podcast.title) (force: \(forceRefresh))")
                #endif
                
                self.fetchAndCacheEpisodes(for: podcast) { episodes, error in
                    Task { @MainActor in
                        self.isLoadingEpisodes[podcastID] = false
                        
                        if let error = error {
                            self.loadingErrors[podcastID] = error
                            
                            // If we have stale cache data, return it as fallback
                            self.getCachedEpisodesAsync(for: podcastID, ignoreExpiry: true) { staleEpisodes in
                                if let episodes = staleEpisodes {
                                    #if canImport(OSLog)
                                    self.logger.warning("Using stale cache as fallback for \(podcast.title, privacy: .public)")
                                    #else
                                    print("⚠️ Using stale cache as fallback for \(podcast.title)")
                                    #endif
                                    completion(episodes)
                                } else {
                                    completion([])
                                }
                            }
                        } else {
                            self.loadingErrors[podcastID] = nil
                            completion(episodes)
                        }
                    }
                }
            }
        }
    }
    
    // PERFORMANCE FIX: Async version of getCachedEpisodes to prevent blocking
    private func getCachedEpisodesAsync(for podcastID: UUID, ignoreExpiry: Bool = false, completion: @escaping ([Episode]?) -> Void) {
        cacheQueue.async { [weak self] in
            guard let self = self else { 
                completion(nil)
                return 
            }
            
            guard let entry = self.episodeCache[podcastID] else {
                completion(nil)
                return
            }
            
            if ignoreExpiry || !entry.isExpired {
                completion(entry.episodes)
            } else {
                completion(nil)
            }
        }
    }
    
    /// Get cached episodes synchronously - CRITICAL FIX for async queue issues
    /// - Parameter podcastID: The podcast ID
    /// - Returns: Cached episodes or nil if not cached or expired
    func getCachedEpisodesSync(for podcastID: UUID) -> [Episode]? {
        print("🔍 EpisodeCacheService: getCachedEpisodesSync called for podcast ID: \(podcastID)")
        print("🔍 EpisodeCacheService: Cache loaded: \(isCacheLoaded), Cache entries: \(episodeCache.count)")
        
        guard let entry = episodeCache[podcastID] else {
            print("❌ EpisodeCacheService: No cache entry found for podcast ID: \(podcastID)")
            print("🔍 EpisodeCacheService: Available cache keys: \(Array(episodeCache.keys))")
            return nil
        }
        
        if entry.isExpired {
            print("⚠️ EpisodeCacheService: Cache entry expired for podcast ID: \(podcastID)")
            return nil
        }
        
        print("✅ EpisodeCacheService: Found \(entry.episodes.count) cached episodes for podcast ID: \(podcastID)")
        return entry.episodes
    }
    
    /// Get cached episodes immediately (synchronously) if available - DEPRECATED
    /// Use getCachedEpisodesAsync instead for better performance
    /// - Parameter podcastID: The podcast ID
    /// - Returns: Cached episodes or nil if not cached or expired
    func getCachedEpisodes(for podcastID: UUID, completion: @escaping ([Episode]?) -> Void) {
        print("🔍 EpisodeCacheService: getCachedEpisodes called for podcast ID: \(podcastID)")
        print("🔍 EpisodeCacheService: Cache loaded: \(isCacheLoaded), Cache entries: \(episodeCache.count)")
        
        cacheQueue.async { [weak self] in
            guard let self = self else {
                print("❌ EpisodeCacheService: Self is nil")
                Task { @MainActor in completion(nil) }
                return
            }
            
            guard let entry = self.episodeCache[podcastID] else {
                print("❌ EpisodeCacheService: No cache entry found for podcast ID: \(podcastID)")
                print("🔍 EpisodeCacheService: Available cache keys: \(Array(self.episodeCache.keys))")
                Task { @MainActor in completion(nil) }
                return
            }
            
            if entry.isExpired {
                print("⚠️ EpisodeCacheService: Cache entry expired for podcast ID: \(podcastID)")
                Task { @MainActor in completion(nil) }
                return
            }
            
            print("✅ EpisodeCacheService: Found \(entry.episodes.count) cached episodes for podcast ID: \(podcastID)")
            Task { @MainActor in completion(entry.episodes) }
        }
    }
    
    /// Check if episodes are cached and not expired for a podcast
    /// - Parameter podcastID: The podcast ID
    /// - Returns: True if fresh cached data is available
    func hasFreshCache(for podcastID: UUID, completion: @escaping (Bool) -> Void) {
        cacheQueue.async { [weak self] in
            guard let self = self,
                  let entry = self.episodeCache[podcastID] else {
                Task { @MainActor in completion(false) }
                return
            }
            Task { @MainActor in completion(!entry.isExpired) }
        }
    }
    
    /// Clear cache for a specific podcast
    /// - Parameter podcastID: The podcast ID to clear cache for
    func clearCache(for podcastID: UUID) {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.episodeCache.removeValue(forKey: podcastID)
            // PERFORMANCE FIX: Save cache asynchronously to prevent blocking
            DispatchQueue.global(qos: .utility).async {
                self?.saveCacheToDisk()
            }
        }
        
        Task { @MainActor [weak self] in
            self?.isLoadingEpisodes[podcastID] = false
            self?.loadingErrors.removeValue(forKey: podcastID)
        }
    }
    
    /// Clear all cached episodes
    func clearAllCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.episodeCache.removeAll()
            // PERFORMANCE FIX: Save cache asynchronously to prevent blocking
            DispatchQueue.global(qos: .utility).async {
                self?.saveCacheToDisk()
            }
        }
        
        Task { @MainActor [weak self] in
            self?.isLoadingEpisodes.removeAll()
            self?.loadingErrors.removeAll()
        }
    }
    
    /// Get cache statistics
    func getCacheStats(completion: @escaping ((totalPodcasts: Int, freshEntries: Int, expiredEntries: Int, totalSizeKB: Double)) -> Void) {
        cacheQueue.async { [weak self] in
            guard let self = self else {
                Task { @MainActor in completion((0, 0, 0, 0)) }
                return
            }
            
            let total = self.episodeCache.count
            let fresh = self.episodeCache.values.filter { !$0.isExpired }.count
            let expired = total - fresh
            
            // Rough size estimation
            let averageEpisodeSize = 1.0 // KB per episode (rough estimate)
            let totalEpisodes = self.episodeCache.values.reduce(0) { $0 + $1.episodes.count }
            let sizeKB = Double(totalEpisodes) * averageEpisodeSize
            
            Task { @MainActor in
                completion((total, fresh, expired, sizeKB))
            }
        }
    }

    /// Approximate memory footprint of the in-memory cache in bytes
    func getCacheMemoryUsage(completion: @escaping (Int) -> Void) {
        cacheQueue.async { [weak self] in
            guard let self = self else {
                Task { @MainActor in completion(0) }
                return
            }
            
            let usage = self.episodeCache.values.reduce(0) { result, entry in
                let data = try? JSONEncoder().encode(entry.episodes)
                return result + (data?.count ?? 0)
            }
            
            Task { @MainActor in
                completion(usage)
            }
        }
    }

    /// Manually trigger migration from legacy UserDefaults storage
    func migrateLegacyCacheIfNeeded() {
        // Migration is now handled automatically in loadCacheFromDisk()
        loadCacheFromDisk()
    }

    // MARK: - Private Methods
    
    /// Invalidate the entire episode cache once to clear out potentially corrupted empty entries from a previous bug.
    private func invalidateCacheOnFirstLaunchAfterFix() {
        let cacheInvalidationFlagKey = "didInvalidateEpisodeCache_v2"
        
        if !UserDefaults.standard.bool(forKey: cacheInvalidationFlagKey) {
            #if canImport(OSLog)
            logger.info("Performing one-time cache invalidation to fix empty episode entries.")
            #else
            print("🔧 Performing one-time cache invalidation to fix empty episode entries.")
            #endif
            
            clearAllCache()
            
            UserDefaults.standard.set(true, forKey: cacheInvalidationFlagKey)
            
            #if canImport(OSLog)
            logger.info("Cache invalidation complete.")
            #else
            print("✅ Cache invalidation complete.")
            #endif
        }
    }
    
    private func fetchAndCacheEpisodes(for podcast: Podcast, completion: @escaping ([Episode], String?) -> Void) {
        // PERFORMANCE FIX: Ensure fetching happens on background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            PodcastService.shared.fetchEpisodes(for: podcast) { episodes in
                guard let self = self else { 
                    completion([], "Service unavailable")
                    return 
                }
                
                // CRITICAL FIX: Only cache if we actually have episodes. Do not cache empty arrays.
                if !episodes.isEmpty {
                    // Cache the episodes asynchronously
                    self.cacheEpisodes(episodes, for: podcast.id)
                    
                    #if canImport(OSLog)
                    self.logger.info("Cached \(episodes.count) episodes for \(podcast.title, privacy: .public)")
                    #else
                    print("💾 Cached \(episodes.count) episodes for \(podcast.title)")
                    #endif
                    
                    completion(episodes, nil)
                } else {
                    #if canImport(OSLog)
                    self.logger.warning("No episodes found for \(podcast.title, privacy: .public), not caching empty result.")
                    #else
                    print("⚠️ No episodes found for \(podcast.title), not caching empty result.")
                    #endif
                    completion([], "No episodes found")
                }
            }
        }
    }
    
    private func cacheEpisodes(_ episodes: [Episode], for podcastID: UUID, lastModified: String? = nil) {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let entry = CacheEntry(
                episodes: episodes,
                timestamp: Date(),
                lastModified: lastModified
            )
            
            self.episodeCache[podcastID] = entry
            
            // Manage cache size to prevent memory issues
            self.manageCacheSize()
            
            // PERFORMANCE FIX: Save to disk asynchronously
            DispatchQueue.global(qos: .utility).async {
                self.saveCacheToDisk()
            }
        }
    }

    /// Update cache with the given episodes for a podcast
    /// - Parameters:
    ///   - episodes: Episodes to store in cache
    ///   - podcastID: Podcast identifier
    func updateCache(_ episodes: [Episode], for podcastID: UUID) {
        cacheEpisodes(episodes, for: podcastID)
    }
    
    // PERFORMANCE FIX: Make cache persistence fully async to prevent blocking
    private func saveCacheToDisk() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            var entries: [String: CacheData] = [:]
            for (uuid, entry) in self.episodeCache {
                entries[uuid.uuidString] = CacheData(
                    episodes: entry.episodes,
                    timestamp: entry.timestamp.timeIntervalSince1970,
                    lastModified: entry.lastModified
                )
            }
            let cacheContainer = CacheContainer(entries: entries)
            
            // Save to file storage asynchronously
            _ = FileStorage.shared.save(cacheContainer, to: "episodeCacheData.json")
        }
    }
    
    private func loadCacheFromDisk() {
        // Try to migrate from UserDefaults first, then load from file
        if let migratedCache = FileStorage.shared.migrateFromUserDefaults(CacheContainer.self, userDefaultsKey: persistenceKey, filename: "episodeCacheData.json") {
            updateCacheFromContainer(migratedCache)
        } else {
            FileStorage.shared.loadAsync(CacheContainer.self, from: "episodeCacheData.json") { [weak self] container in
                if let container = container {
                    self?.updateCacheFromContainer(container)
                } else {
                    // No cache file exists, mark as loaded anyway
                    self?.cacheQueue.async(flags: .barrier) {
                        self?.isCacheLoaded = true
                        let completions = self?.cacheLoadingCompletions ?? []
                        self?.cacheLoadingCompletions.removeAll()
                        
                        print("💾 No cache file found - starting with empty cache")
                        
                        // Execute waiting completions
                        DispatchQueue.main.async {
                            for completion in completions {
                                completion()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func updateCacheFromContainer(_ container: CacheContainer) {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            for (uuidString, cacheData) in container.entries {
                if let uuid = UUID(uuidString: uuidString) {
                    let entry = CacheEntry(
                        episodes: cacheData.episodes,
                        timestamp: Date(timeIntervalSince1970: cacheData.timestamp),
                        lastModified: cacheData.lastModified
                    )
                    self.episodeCache[uuid] = entry
                }
            }
            
            // Manage cache size after loading
            self.manageCacheSize()
            
            // Mark cache as loaded and notify waiting completions
            self.isCacheLoaded = true
            let completions = self.cacheLoadingCompletions
            self.cacheLoadingCompletions.removeAll()
            
            #if canImport(OSLog)
            self.logger.info("Loaded \(container.entries.count) cached podcast episodes from disk")
            #else
            print("💾 Loaded \(container.entries.count) cached podcast episodes from disk")
            #endif
            
            // Execute waiting completions
            DispatchQueue.main.async {
                for completion in completions {
                    completion()
                }
            }
        }
    }
    
    // MARK: - Cache Maintenance
    
    private func startCacheCleanupTimer() {
        Timer.scheduledTimer(withTimeInterval: 60 * 5, repeats: true) { [weak self] _ in
            self?.cleanupExpiredEntries()
        }
    }
    
    private func manageCacheSize() {
        // This should be called from within cacheQueue.async(flags: .barrier)
        if episodeCache.count > maxCacheEntries {
            // Remove oldest entries based on timestamp
            let sortedEntries = episodeCache.sorted { $0.value.timestamp < $1.value.timestamp }
            let entriesToRemove = sortedEntries.prefix(episodeCache.count - maxCacheEntries)
            
            for (podcastID, _) in entriesToRemove {
                episodeCache.removeValue(forKey: podcastID)
            }
            
            #if canImport(OSLog)
            logger.info("Trimmed cache to \(self.maxCacheEntries) entries to prevent memory issues")
            #else
            print("🧹 Trimmed cache to \(self.maxCacheEntries) entries to prevent memory issues")
            #endif
        }
    }
    
    private func cleanupExpiredEntries() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let originalCount = self.episodeCache.count
            
            // Remove entries older than 2 hours
            let maxAge: TimeInterval = 2 * 60 * 60
            self.episodeCache = self.episodeCache.filter { _, entry in
                entry.age < maxAge
            }
            
            let removedCount = originalCount - self.episodeCache.count
            
            if removedCount > 0 {
                #if canImport(OSLog)
                self.logger.info("Cleaned up \(removedCount) old cache entries")
                #else
                print("🧹 Cleaned up \(removedCount) old cache entries")
                #endif
                self.saveCacheToDisk()
            }
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
#if DEBUG
    /// Insert a cache entry for testing purposes
    func insertCache(episodes: [Episode], for podcastID: UUID, timestamp: Date = Date()) {
        cacheQueue.async(flags: .barrier) {
            let entry = CacheEntry(episodes: episodes, timestamp: timestamp, lastModified: nil)
            self.episodeCache[podcastID] = entry
        }
    }
#endif

    /// Populate cache from global episodes in UnifiedEpisodeController
    /// This ensures that episodes loaded globally are available for individual podcast views
    @MainActor
    func populateCacheFromGlobalEpisodes() {
        let globalEpisodes = UnifiedEpisodeController.shared.episodes
        
        print("🔄 EpisodeCacheService: populateCacheFromGlobalEpisodes called")
        print("🔄 EpisodeCacheService: Global episodes count: \(globalEpisodes.count)")
        
        guard !globalEpisodes.isEmpty else {
            print("⚠️ EpisodeCacheService: No global episodes to populate cache with")
            return
        }
        
        // Group episodes by podcast ID
        let episodesByPodcast = Dictionary(grouping: globalEpisodes) { episode in
            episode.podcastID
        }
        
        print("🔄 EpisodeCacheService: Episodes grouped into \(episodesByPodcast.count) podcasts")
        for (podcastID, episodes) in episodesByPodcast {
            if let podcastID = podcastID {
                print("   - Podcast \(podcastID): \(episodes.count) episodes")
            } else {
                print("   - Podcast with nil ID: \(episodes.count) episodes")
            }
        }
        
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let initialCacheCount = self.episodeCache.count
            var populatedCount = 0
            
            for (podcastID, episodes) in episodesByPodcast {
                guard let podcastID = podcastID else { continue }
                
                // Only populate if we don't already have a cache entry for this podcast
                if self.episodeCache[podcastID] == nil {
                    let entry = CacheEntry(
                        episodes: episodes,
                        timestamp: Date(),
                        lastModified: nil
                    )
                    self.episodeCache[podcastID] = entry
                    populatedCount += 1
                    print("✅ EpisodeCacheService: Populated cache for podcast \(podcastID) with \(episodes.count) episodes")
                } else {
                    print("ℹ️ EpisodeCacheService: Cache already exists for podcast \(podcastID), skipping")
                }
            }
            
            print("🔄 EpisodeCacheService: Populated \(populatedCount) new cache entries. Total cache entries: \(self.episodeCache.count)")
            
            // Save the updated cache if we created new entries
            if populatedCount > 0 {
                print("💾 EpisodeCacheService: Saving updated cache with \(populatedCount) new entries")
                DispatchQueue.global(qos: .utility).async {
                    self.saveCacheToDisk()
                }
            }
        }
    }
}

// MARK: - Cache Extension for UnifiedEpisodeController Integration

extension EpisodeCacheService {
    /// Sync cached episodes with UnifiedEpisodeController
    /// This ensures the global episode list stays updated
    @MainActor
    func syncWithUnifiedEpisodeController(episodes: [Episode]) {
        // Add episodes to the global episode list if they don't exist
        let _ = UnifiedEpisodeController.shared
        // Note: UnifiedEpisodeController doesn't have addEpisodes method
        // This functionality is now handled by the repository
        // episodeController.addEpisodes(episodes)
    }
    
    /// Get all cached episodes from all podcasts for restoration purposes
    /// - Parameter completion: Completion handler with all cached episodes
    func getAllCachedEpisodes(completion: @escaping ([Episode]) -> Void) {
        // Check if cache is already loaded
        cacheQueue.async { [weak self] in
            guard let self = self else { 
                completion([])
                return 
            }
            
            if self.isCacheLoaded {
                // Cache is loaded, return episodes immediately
                var allEpisodes: [Episode] = []
                for (_, entry) in self.episodeCache {
                    allEpisodes.append(contentsOf: entry.episodes)
                }
                
                print("📦 EpisodeCacheService: Found \(allEpisodes.count) total cached episodes across \(self.episodeCache.count) podcasts")
                DispatchQueue.main.async {
                    completion(allEpisodes)
                }
            } else {
                // Cache not loaded yet, wait for it
                print("⏳ EpisodeCacheService: Cache not loaded yet, waiting...")
                self.cacheLoadingCompletions.append {
                    self.cacheQueue.async {
                        var allEpisodes: [Episode] = []
                        for (_, entry) in self.episodeCache {
                            allEpisodes.append(contentsOf: entry.episodes)
                        }
                        
                        print("📦 EpisodeCacheService: Found \(allEpisodes.count) total cached episodes across \(self.episodeCache.count) podcasts (after waiting)")
                        completion(allEpisodes)
                    }
                }
            }
        }
    }
} 