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
#if canImport(OSLog)
    private let logger = Logger(subsystem: "com.jimmy.app", category: "cache")
#endif
    
    // MARK: - Published Properties
    
    @Published var isLoadingEpisodes: [UUID: Bool] = [:]
    @Published var loadingErrors: [UUID: String] = [:]
    
    // MARK: - Initialization
    
    private init() {
        // Load cache data (will migrate from UserDefaults if needed)
        loadCacheFromDisk()
        
        startCacheCleanupTimer()
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
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            let podcastID = podcast.id
            
            // Update loading state
            DispatchQueue.main.async {
                self.isLoadingEpisodes[podcastID] = true
                self.loadingErrors[podcastID] = nil
            }
            
            // Check cache first (unless force refresh is requested)
            if !forceRefresh, let cachedEntry = self.episodeCache[podcastID], !cachedEntry.isExpired {
                #if canImport(OSLog)
                logger.info("Using cached episodes for \(podcast.title, privacy: .public) (age: \(Int(cachedEntry.age/60))m)")
                #else
                print("📱 Using cached episodes for \(podcast.title) (age: \(Int(cachedEntry.age/60))m)")
                #endif
                
                DispatchQueue.main.async {
                    self.isLoadingEpisodes[podcastID] = false
                    completion(cachedEntry.episodes)
                }
                return
            }
            
            // If offline, return cached data if available
            if !NetworkMonitor.shared.isConnected {
                if let cachedEntry = self.episodeCache[podcastID] {
                    #if canImport(OSLog)
                    logger.info("Offline - using cached episodes for \(podcast.title, privacy: .public)")
                    #else
                    print("📡 Offline - using cached episodes for \(podcast.title)")
                    #endif
                    DispatchQueue.main.async {
                        self.isLoadingEpisodes[podcastID] = false
                        self.loadingErrors[podcastID] = "You appear to be offline. Showing cached episodes."
                        completion(cachedEntry.episodes)
                    }
                    return
                } else {
                    DispatchQueue.main.async {
                        self.isLoadingEpisodes[podcastID] = false
                        self.loadingErrors[podcastID] = "You appear to be offline."
                        completion([])
                    }
                    return
                }
            }

            // Cache miss or expired - fetch fresh data
            let cacheAge = self.episodeCache[podcastID]?.age ?? 0
            #if canImport(OSLog)
            logger.info("Fetching fresh episodes for \(podcast.title, privacy: .public) (cache age: \(Int(cacheAge/60))m, force: \(forceRefresh))")
            #else
            print("🌐 Fetching fresh episodes for \(podcast.title) (cache age: \(Int(cacheAge/60))m, force: \(forceRefresh))")
            #endif
            
            self.fetchAndCacheEpisodes(for: podcast) { episodes, error in
                DispatchQueue.main.async {
                    self.isLoadingEpisodes[podcastID] = false
                    
                    if let error = error {
                        self.loadingErrors[podcastID] = error
                        
                        // If we have stale cache data, return it as fallback
                        if let staleEntry = self.episodeCache[podcastID] {
                            #if canImport(OSLog)
                            logger.warning("Using stale cache as fallback for \(podcast.title, privacy: .public)")
                            #else
                            print("⚠️ Using stale cache as fallback for \(podcast.title)")
                            #endif
                            completion(staleEntry.episodes)
                        } else {
                            completion([])
                        }
                    } else {
                        self.loadingErrors[podcastID] = nil
                        completion(episodes)
                    }
                }
            }
        }
    }
    
    /// Get cached episodes immediately (synchronously) if available
    /// - Parameter podcastID: The podcast ID
    /// - Returns: Cached episodes or nil if not cached or expired
    func getCachedEpisodes(for podcastID: UUID) -> [Episode]? {
        return cacheQueue.sync {
            guard let entry = episodeCache[podcastID], !entry.isExpired else {
                return nil
            }
            return entry.episodes
        }
    }
    
    /// Check if episodes are cached and not expired for a podcast
    /// - Parameter podcastID: The podcast ID
    /// - Returns: True if fresh cached data is available
    func hasFreshCache(for podcastID: UUID) -> Bool {
        return cacheQueue.sync {
            guard let entry = episodeCache[podcastID] else { return false }
            return !entry.isExpired
        }
    }
    
    /// Clear cache for a specific podcast
    /// - Parameter podcastID: The podcast ID to clear cache for
    func clearCache(for podcastID: UUID) {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.episodeCache.removeValue(forKey: podcastID)
            self?.saveCacheToDisk()
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.isLoadingEpisodes[podcastID] = false
            self?.loadingErrors.removeValue(forKey: podcastID)
        }
    }
    
    /// Clear all cached episodes
    func clearAllCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.episodeCache.removeAll()
            self?.saveCacheToDisk()
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.isLoadingEpisodes.removeAll()
            self?.loadingErrors.removeAll()
        }
    }
    
    /// Get cache statistics
    func getCacheStats() -> (totalPodcasts: Int, freshEntries: Int, expiredEntries: Int, totalSizeKB: Double) {
        return cacheQueue.sync {
            let total = episodeCache.count
            let fresh = episodeCache.values.filter { !$0.isExpired }.count
            let expired = total - fresh
            
            // Rough size estimation
            let averageEpisodeSize = 1.0 // KB per episode (rough estimate)
            let totalEpisodes = episodeCache.values.reduce(0) { $0 + $1.episodes.count }
            let sizeKB = Double(totalEpisodes) * averageEpisodeSize
            
            return (total, fresh, expired, sizeKB)
        }
    }

    /// Approximate memory footprint of the in-memory cache in bytes
    func getCacheMemoryUsage() -> Int {
        return cacheQueue.sync {
            episodeCache.values.reduce(0) { result, entry in
                let data = try? JSONEncoder().encode(entry.episodes)
                return result + (data?.count ?? 0)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func fetchAndCacheEpisodes(
        for podcast: Podcast,
        completion: @escaping ([Episode], String?) -> Void
    ) {
        PodcastService.shared.fetchEpisodes(for: podcast) { [weak self] episodes in
            guard let self = self else { 
                completion([], "Service unavailable")
                return 
            }
            
            if episodes.isEmpty {
                completion([], "Unable to load episodes. Please check your internet connection and try again.")
                return
            }
            
            // Cache the episodes safely
            self.cacheQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                
                let entry = CacheEntry(
                    episodes: episodes,
                    timestamp: Date(),
                    lastModified: nil // Could be enhanced with HTTP headers
                )
                
                self.episodeCache[podcast.id] = entry
                self.saveCacheToDisk()

                #if canImport(OSLog)
                logger.info("Cached \(episodes.count) episodes for \(podcast.title, privacy: .public)")
                #else
                print("💾 Cached \(episodes.count) episodes for \(podcast.title)")
                #endif
            }
            
            completion(episodes, nil)
        }
    }
    
    // MARK: - Persistence
    
    private func saveCacheToDisk() {
        guard !episodeCache.isEmpty else { 
            // Delete cache file if cache is empty
            _ = FileStorage.shared.delete("episodeCache.json")
            return 
        }
        
        // Convert cache to Codable format
        var entries: [String: CacheData] = [:]
        
        for (uuid, entry) in episodeCache {
            let cacheData = CacheData(
                episodes: entry.episodes,
                timestamp: entry.timestamp.timeIntervalSince1970,
                lastModified: entry.lastModified
            )
            entries[uuid.uuidString] = cacheData
        }
        
        let container = CacheContainer(entries: entries)
        if FileStorage.shared.save(container, to: "episodeCache.json") {
            // Calculate memory usage directly without calling getCacheMemoryUsage() to avoid deadlock
            let totalEpisodes = episodeCache.values.reduce(0) { $0 + $1.episodes.count }
            let estimatedBytes = totalEpisodes * 1024 // Rough estimate: 1KB per episode
            let mem = formatBytes(estimatedBytes)
            
#if canImport(OSLog)
            logger.info("Episode cache persisted (\(mem) estimated in memory)")
#else
            print("💾 Episode cache persisted (\(mem) estimated in memory)")
#endif
        } else {
            #if canImport(OSLog)
            logger.error("Episode cache not saved due to storage issue")
            #else
            print("⚠️ Episode cache not saved due to storage issue")
            #endif
        }
    }
    
    private func loadCacheFromDisk() {
        // Try to migrate from UserDefaults first, then load from file
        var container: CacheContainer?
        
        // First try to migrate old format from UserDefaults
        if UserDefaults.standard.object(forKey: persistenceKey) != nil {
            #if canImport(OSLog)
            logger.info("Migrating cache from UserDefaults to file storage...")
            #else
            print("📦 Migrating cache from UserDefaults to file storage...")
            #endif
            if let oldData = UserDefaults.standard.object(forKey: persistenceKey) as? [String: [String: Any]] {
                // Convert old format to new format
                var entries: [String: CacheData] = [:]
                
                for (uuidString, entryData) in oldData {
                    guard let episodesBase64 = entryData["episodes"] as? String,
                          let episodesData = Data(base64Encoded: episodesBase64),
                          let episodes = try? JSONDecoder().decode([Episode].self, from: episodesData),
                          let timestampInterval = entryData["timestamp"] as? TimeInterval else {
                        continue
                    }
                    
                    let lastModified = entryData["lastModified"] as? String
                    
                    let cacheData = CacheData(
                        episodes: episodes,
                        timestamp: timestampInterval,
                        lastModified: lastModified
                    )
                    entries[uuidString] = cacheData
                }
                
                container = CacheContainer(entries: entries)
                
                // Save to new format and clear UserDefaults
                if !entries.isEmpty {
                    _ = FileStorage.shared.save(container!, to: "episodeCache.json")
                    #if canImport(OSLog)
                    logger.info("Successfully migrated \(entries.count) cache entries")
                    #else
                    print("📦 Successfully migrated \(entries.count) cache entries")
                    #endif
                }
                UserDefaults.standard.removeObject(forKey: persistenceKey)
            }
        }
        
        // If no migration happened, load from file
        if container == nil {
            container = FileStorage.shared.load(CacheContainer.self, from: "episodeCache.json")
        }
        
        guard let container = container else {
            return
        }
        
        // Convert back to runtime format
        var loadedCache: [UUID: CacheEntry] = [:]
        
        for (uuidString, cacheData) in container.entries {
            guard let uuid = UUID(uuidString: uuidString) else {
                continue
            }
            
            let timestamp = Date(timeIntervalSince1970: cacheData.timestamp)
            
            let entry = CacheEntry(
                episodes: cacheData.episodes,
                timestamp: timestamp,
                lastModified: cacheData.lastModified
            )
            
            loadedCache[uuid] = entry
        }
        
        episodeCache = loadedCache
        #if canImport(OSLog)
        logger.info("Loaded episode cache with \(episodeCache.count) entries from file storage")
        #else
        print("📱 Loaded episode cache with \(episodeCache.count) entries from file storage")
        #endif
    }
    
    // MARK: - Cache Maintenance
    
    private func startCacheCleanupTimer() {
        Timer.scheduledTimer(withTimeInterval: 60 * 5, repeats: true) { [weak self] _ in
            self?.cleanupExpiredEntries()
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
                logger.info("Cleaned up \(removedCount) old cache entries")
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
}

// MARK: - Cache Extension for EpisodeViewModel Integration

extension EpisodeCacheService {
    /// Sync cached episodes with EpisodeViewModel
    /// This ensures the global episode list stays updated
    func syncWithEpisodeViewModel(episodes: [Episode]) {
        // Add episodes to the global episode list if they don't exist
        let episodeViewModel = EpisodeViewModel.shared
        episodeViewModel.addEpisodes(episodes)
    }
} 