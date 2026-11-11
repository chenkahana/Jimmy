import Foundation
import OSLog
import Combine
import UIKit

/// Intelligent Cache Engine with multi-tier caching, smart invalidation, and predictive prefetching
final class IntelligentCacheEngine: ObservableObject {
    private let logger = Logger(subsystem: "Jimmy.IntelligentCache", category: "CacheEngine")
    
    // MARK: - Configuration
    private struct Config {
        static let memoryCapacity = 100 * 1024 * 1024 // 100MB
        static let diskCapacity = 500 * 1024 * 1024   // 500MB
        static let defaultTTL: TimeInterval = 30 * 60  // 30 minutes
        static let freshnessTTL: TimeInterval = 5 * 60 // 5 minutes for freshness checks
        static let maxCacheEntries = 10000
        static let compressionThreshold = 1024 // Compress data larger than 1KB
        
        // PERF-07: Adaptive TTL bounds
        static let minAdaptiveTTL: TimeInterval = 5 * 60    // 5 minutes minimum
        static let maxAdaptiveTTL: TimeInterval = 60 * 60   // 1 hour maximum
    }
    
    // MARK: - Cache Layers
    private let memoryCache = NSCache<NSString, CacheEntry>()
    private let diskCache: DiskCache
    private let metadataCache = NSCache<NSString, CacheMetadata>()
    
    // PERF-07: Adaptive TTL tracking
    private var feedUpdateHistory: [URL: AdaptiveTTLData] = [:]
    private let ttlQueue = DispatchQueue(label: "AdaptiveTTL", attributes: .concurrent)
    
    // MARK: - Cache Management
    private let cacheQueue = DispatchQueue(label: "IntelligentCache", qos: .utility, attributes: .concurrent)
    private var cleanupTimer: Timer?
    
    // MARK: - Performance Tracking
    @Published private(set) var cacheStats = CacheStatistics()
    private var hitCount: Int64 = 0
    private var missCount: Int64 = 0
    
    init() {
        self.diskCache = DiskCache()
        
        // Configure memory cache
        memoryCache.countLimit = Config.maxCacheEntries
        memoryCache.totalCostLimit = Config.memoryCapacity
        
        // Setup cleanup timer
        let timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.performMaintenance() }
        }
        self.cleanupTimer = timer
        
        setupMemoryWarningHandling()
        // Intelligent Cache Engine initialized
    }
    
    deinit {
        cleanupTimer?.invalidate()
    }
    
    // MARK: - PERF-07: Adaptive TTL Calculation
    
    /// Calculates adaptive TTL based on how frequently a feed updates
    func getAdaptiveTTL(for feedURL: URL) -> TimeInterval {
        var ttlData: AdaptiveTTLData?
        
        ttlQueue.sync {
            ttlData = feedUpdateHistory[feedURL]
        }
        
        guard let data = ttlData else {
            // No history - use default TTL
            return Config.defaultTTL
        }
        
        return data.recommendedTTL
    }
    
    /// Record an update check for a feed (call this after fetching feed data)
    func recordFeedCheck(for feedURL: URL, hadNewContent: Bool) {
        ttlQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            var data = self.feedUpdateHistory[feedURL] ?? AdaptiveTTLData()
            data.recordCheck(hadNewContent: hadNewContent)
            self.feedUpdateHistory[feedURL] = data
        }
    }
    
    // MARK: - Podcast Caching
    
    func getCachedPodcasts() async -> [EnhancedPodcast]? {
        let key = "podcasts_list"
        
        if let cached = await getCachedData(key: key, type: [EnhancedPodcast].self) {
            recordHit()
            // Memory cache hit for podcasts list
            return cached
        }
        
        recordMiss()
        return nil
    }
    
    func cachePodcasts(_ podcasts: [EnhancedPodcast]) async {
        let key = "podcasts_list"
        await cacheData(podcasts, key: key, ttl: Config.defaultTTL)
        // Cached podcasts
    }
    
    func cachePodcast(_ podcast: EnhancedPodcast, with episodes: [Episode]) async {
        // Cache podcast individually
        let podcastKey = "podcast_\(podcast.id.uuidString)"
        
        // PERF-07: Use adaptive TTL based on feed update frequency
        let adaptiveTTL = getAdaptiveTTL(for: podcast.feedURL)
        await cacheData(podcast, key: podcastKey, ttl: adaptiveTTL)
        
        // Cache episodes for this podcast
        await cacheEpisodesWithAdaptiveTTL(episodes, for: podcast.id, feedURL: podcast.feedURL)
        
        // Cached podcast with episodes
    }
    
    // MARK: - Episode Caching
    
    func getCachedEpisodes(for podcastID: UUID) async -> [Episode]? {
        let key = "episodes_\(podcastID.uuidString)"
        
        if let cached = await getCachedData(key: key, type: [Episode].self) {
            recordHit()
            // Cache hit for episodes
            return cached
        }
        
        recordMiss()
        return nil
    }
    
    func cacheEpisodes(_ episodes: [Episode], for podcastID: UUID) async {
        let key = "episodes_\(podcastID.uuidString)"
        await cacheData(episodes, key: key, ttl: Config.defaultTTL)
        
        // Also cache individual episodes for granular access
        for episode in episodes {
            let episodeKey = "episode_\(episode.id.uuidString)"
            await cacheData(episode, key: episodeKey, ttl: Config.defaultTTL * 2) // Episodes last longer
        }
        
        // Cached episodes
    }
    
    /// PERF-07: Cache episodes with adaptive TTL based on feed update frequency
    private func cacheEpisodesWithAdaptiveTTL(_ episodes: [Episode], for podcastID: UUID, feedURL: URL) async {
        let key = "episodes_\(podcastID.uuidString)"
        let adaptiveTTL = getAdaptiveTTL(for: feedURL)
        
        await cacheData(episodes, key: key, ttl: adaptiveTTL)
        
        // Also cache individual episodes for granular access
        for episode in episodes {
            let episodeKey = "episode_\(episode.id.uuidString)"
            await cacheData(episode, key: episodeKey, ttl: adaptiveTTL * 2) // Episodes last longer
        }
    }
    
    func cacheEpisode(_ episode: Episode, for podcastID: UUID) async {
        let episodeKey = "episode_\(episode.id.uuidString)"
        await cacheData(episode, key: episodeKey, ttl: Config.defaultTTL * 2)
        
        // Update episodes list cache incrementally
        await updateEpisodesListCache(adding: episode, for: podcastID)
    }
    
    // MARK: - Freshness Management
    
    func isFresh(_ feedURL: URL) async -> Bool {
        let key = "freshness_\(feedURL.absoluteString.hash)"
        
        if let metadata = metadataCache.object(forKey: NSString(string: key)) {
            let age = Date().timeIntervalSince(metadata.timestamp)
            
            // PERF-07: Use adaptive freshness based on feed update frequency
            let adaptiveFreshness = min(getAdaptiveTTL(for: feedURL) / 6, Config.freshnessTTL)
            let isFresh = age < adaptiveFreshness
            
            return isFresh
        }
        
        return false
    }
    
    func markFresh(_ feedURL: URL) async {
        let key = "freshness_\(feedURL.absoluteString.hash)"
        
        // PERF-07: Use adaptive freshness TTL
        let adaptiveFreshness = min(getAdaptiveTTL(for: feedURL) / 6, Config.freshnessTTL)
        
        let metadata = CacheMetadata(
            timestamp: Date(),
            ttl: adaptiveFreshness,
            size: 0,
            accessCount: 1
        )
        
        metadataCache.setObject(metadata, forKey: NSString(string: key))
        // Marked feed as fresh
    }
    
    // MARK: - Smart Invalidation
    
    func invalidateCache(for podcastID: UUID) async {
        let podcastKey = "podcast_\(podcastID.uuidString)"
        let episodesKey = "episodes_\(podcastID.uuidString)"
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await self?.removeCachedData(key: podcastKey)
            }
            
            group.addTask { [weak self] in
                await self?.removeCachedData(key: episodesKey)
            }
        }
        
        // Invalidate podcasts list to trigger refresh
        await removeCachedData(key: "podcasts_list")
        
        // Invalidated cache for podcast
    }
    
    func invalidateAllCaches() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                self?.memoryCache.removeAllObjects()
            }
            
            group.addTask { [weak self] in
                self?.metadataCache.removeAllObjects()
            }
            
            group.addTask { [weak self] in
                await self?.diskCache.removeAll()
            }
        }
        
        // Invalidated all caches
    }
    
    // MARK: - Generic Cache Operations
    
    private func getCachedData<T: Codable>(key: String, type: T.Type) async -> T? {
        // Try memory cache first
        if let entry = memoryCache.object(forKey: NSString(string: key)) {
            if !entry.isExpired {
                entry.updateAccessTime()
                return entry.data as? T
            } else {
                memoryCache.removeObject(forKey: NSString(string: key))
            }
        }
        
        // Try disk cache
        if let data = await diskCache.getData(for: key) {
            do {
                let decoded = try JSONDecoder().decode(CacheWrapper<T>.self, from: data)
                if !decoded.isExpired {
                    // Promote to memory cache
                    let entry = CacheEntry(data: decoded.data, ttl: decoded.ttl)
                    memoryCache.setObject(entry, forKey: NSString(string: key))
                    return decoded.data
                } else {
                    await diskCache.removeData(for: key)
                }
            } catch {
                logger.error("❌ Failed to decode cached data for key \(key): \(error)")
                await diskCache.removeData(for: key)
            }
        }
        
        return nil
    }
    
    private func cacheData<T: Codable>(_ data: T, key: String, ttl: TimeInterval) async {
        let entry = CacheEntry(data: data, ttl: ttl)
        
        // Store in memory cache
        memoryCache.setObject(entry, forKey: NSString(string: key), cost: entry.estimatedSize)
        
        // Store in disk cache asynchronously
        Task.detached(priority: .utility) { [weak self] in
            do {
                let wrapper = CacheWrapper(data: data, ttl: ttl)
                let encoded = try JSONEncoder().encode(wrapper)
                await self?.diskCache.setData(encoded, for: key)
            } catch {
                self?.logger.error("❌ Failed to encode data for caching: \(error)")
            }
        }
        
        updateCacheStats()
    }
    
    private func removeCachedData(key: String) async {
        memoryCache.removeObject(forKey: NSString(string: key))
        await diskCache.removeData(for: key)
    }
    
    // MARK: - Incremental Updates
    
    private func updateEpisodesListCache(adding episode: Episode, for podcastID: UUID) async {
        let key = "episodes_\(podcastID.uuidString)"
        
        if var existingEpisodes = await getCachedData(key: key, type: [Episode].self) {
            // Check if episode already exists
            if !existingEpisodes.contains(where: { $0.id == episode.id }) {
                existingEpisodes.insert(episode, at: 0) // Add at beginning (newest first)
                await cacheData(existingEpisodes, key: key, ttl: Config.defaultTTL)
                // Updated episodes cache
            }
        }
    }
    
    // MARK: - Performance Monitoring
    
    private func recordHit() {
        OSAtomicIncrement64(&hitCount)
        updateCacheStats()
    }
    
    private func recordMiss() {
        OSAtomicIncrement64(&missCount)
        updateCacheStats()
    }
    
    private func updateCacheStats() {
        let totalRequests = hitCount + missCount
        let hitRate = totalRequests > 0 ? Double(hitCount) / Double(totalRequests) : 0.0
        
        DispatchQueue.main.async { [weak self] in
            self?.cacheStats = CacheStatistics(
                hitRate: hitRate,
                totalHits: self?.hitCount ?? 0,
                totalMisses: self?.missCount ?? 0,
                memoryUsage: Int64(self?.memoryCache.totalCostLimit ?? 0),
                diskUsage: 0 // TODO: Implement disk usage tracking
            )
        }
    }
    
    // MARK: - Maintenance
    
    private func performMaintenance() async {
        // Performing cache maintenance
        
        // Clean expired entries from memory cache
        // Note: NSCache handles this automatically, but we can be more aggressive
        
        // Clean disk cache
        await diskCache.cleanExpiredEntries()
        
        // Update statistics
        updateCacheStats()
        
        // Cache maintenance completed
    }
    
    private func setupMemoryWarningHandling() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }
    
    private func handleMemoryWarning() {
        logger.warning("⚠️ Memory warning received - clearing memory cache")
        memoryCache.removeAllObjects()
        metadataCache.removeAllObjects()
    }
}

// MARK: - Supporting Types

private class CacheEntry: NSObject {
    let data: Any
    let timestamp: Date
    let ttl: TimeInterval
    private var lastAccess: Date
    
    init(data: Any, ttl: TimeInterval) {
        self.data = data
        self.timestamp = Date()
        self.ttl = ttl
        self.lastAccess = Date()
        super.init()
    }
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > ttl
    }
    
    func updateAccessTime() {
        lastAccess = Date()
    }
    
    var estimatedSize: Int {
        // Rough estimation of memory usage
        if let data = data as? Data {
            return data.count
        } else if let string = data as? String {
            return string.utf8.count
        } else {
            return 1024 // Default estimate
        }
    }
}

private struct CacheWrapper<T: Codable>: Codable {
    let data: T
    let timestamp: Date
    let ttl: TimeInterval
    
    init(data: T, ttl: TimeInterval) {
        self.data = data
        self.timestamp = Date()
        self.ttl = ttl
    }
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > ttl
    }
}

private class CacheMetadata: NSObject {
    let timestamp: Date
    let ttl: TimeInterval
    let size: Int
    var accessCount: Int
    
    init(timestamp: Date, ttl: TimeInterval, size: Int, accessCount: Int) {
        self.timestamp = timestamp
        self.ttl = ttl
        self.size = size
        self.accessCount = accessCount
        super.init()
    }
}

struct CacheStatistics {
    let hitRate: Double
    let totalHits: Int64
    let totalMisses: Int64
    let memoryUsage: Int64
    let diskUsage: Int64
    
    init(hitRate: Double = 0, totalHits: Int64 = 0, totalMisses: Int64 = 0, memoryUsage: Int64 = 0, diskUsage: Int64 = 0) {
        self.hitRate = hitRate
        self.totalHits = totalHits
        self.totalMisses = totalMisses
        self.memoryUsage = memoryUsage
        self.diskUsage = diskUsage
    }
}

// MARK: - PERF-07: Adaptive TTL Data

/// Tracks feed update history to calculate optimal cache TTL
/// Feeds that update frequently get shorter TTLs, stable feeds get longer TTLs
struct AdaptiveTTLData {
    var lastChecks: [Date] = []
    var lastUpdates: [Date] = []
    
    // Configuration
    private static let historySize = 10
    private static let minTTL: TimeInterval = 5 * 60    // 5 minutes
    private static let maxTTL: TimeInterval = 60 * 60   // 1 hour
    private static let defaultTTL: TimeInterval = 30 * 60 // 30 minutes
    
    /// Calculate the recommended TTL based on update frequency
    var recommendedTTL: TimeInterval {
        guard lastUpdates.count >= 2 else {
            // Not enough data - use default
            return Self.defaultTTL
        }
        
        // Calculate average time between updates
        var intervals: [TimeInterval] = []
        for i in 1..<lastUpdates.count {
            let interval = lastUpdates[i-1].timeIntervalSince(lastUpdates[i])
            if interval > 0 {
                intervals.append(interval)
            }
        }
        
        guard !intervals.isEmpty else {
            return Self.defaultTTL
        }
        
        let avgUpdateInterval = intervals.reduce(0, +) / Double(intervals.count)
        
        // TTL should be a fraction of the update interval
        // Use 1/4 of the average update interval, clamped to bounds
        let rawTTL = avgUpdateInterval / 4
        return max(Self.minTTL, min(Self.maxTTL, rawTTL))
    }
    
    /// Record a check for this feed
    mutating func recordCheck(hadNewContent: Bool) {
        let now = Date()
        
        // Add to checks history
        lastChecks.insert(now, at: 0)
        if lastChecks.count > Self.historySize {
            lastChecks.removeLast()
        }
        
        // If there was new content, record the update time
        if hadNewContent {
            lastUpdates.insert(now, at: 0)
            if lastUpdates.count > Self.historySize {
                lastUpdates.removeLast()
            }
        }
    }
    
    /// Get a human-readable description of the update frequency
    var updateFrequencyDescription: String {
        guard lastUpdates.count >= 2 else {
            return "Unknown"
        }
        
        let avgInterval = recommendedTTL * 4 // Reverse the 1/4 calculation
        
        if avgInterval < 60 * 60 {
            return "Hourly"
        } else if avgInterval < 24 * 60 * 60 {
            return "Daily"
        } else if avgInterval < 7 * 24 * 60 * 60 {
            return "Weekly"
        } else {
            return "Infrequent"
        }
    }
}

// MARK: - Disk Cache Implementation

private actor DiskCache {
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    init() {
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access caches directory")
        }
        self.cacheDirectory = cachesDirectory.appendingPathComponent("IntelligentCache", isDirectory: true)
        
        // Create cache directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func setData(_ data: Data, for key: String) async {
        let url = cacheDirectory.appendingPathComponent(key.sha256)
        
        do {
            try data.write(to: url)
        } catch {
            // Handle write error silently - disk cache is optional
        }
    }
    
    func getData(for key: String) async -> Data? {
        let url = cacheDirectory.appendingPathComponent(key.sha256)
        
        do {
            return try Data(contentsOf: url)
        } catch {
            return nil
        }
    }
    
    func removeData(for key: String) async {
        let url = cacheDirectory.appendingPathComponent(key.sha256)
        try? fileManager.removeItem(at: url)
    }
    
    func removeAll() async {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func cleanExpiredEntries() async {
        // Implementation would check file modification dates and remove old entries
        // For now, this is a placeholder
    }
}

// MARK: - String Extension for SHA256

import CryptoKit

private extension String {
    var sha256: String {
        let data = Data(self.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
