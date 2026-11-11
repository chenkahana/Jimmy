import Foundation

/// PERF-06: A thread-safe, Codable-based cache for storing and retrieving podcast episodes.
/// Converted to Swift actor for cleaner, modern concurrency without manual DispatchQueue management.
actor EpisodeCacheService {
    static let shared = EpisodeCacheService()
    
    private let fileManager = FileManager.default
    
    // MARK: - Configuration
    private struct Config {
        static let maxCacheSize: Int = 50 * 1024 * 1024 // 50MB max cache size
        static let cacheExpirationInterval: TimeInterval = 60 * 60 // 1 hour
    }
    
    private var cacheDirectory: URL {
        // Use a dedicated directory for episode caches to keep them organized.
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documentsDirectory.appendingPathComponent("AppData").appendingPathComponent("EpisodeCache")
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private init() {
    }
    
    // MARK: - Public API
    
    /// Retrieves the cached episodes for a given podcast ID.
    /// - Parameter podcastId: The `UUID` of the podcast.
    /// - Returns: An array of `Episode` objects or `nil` if not found or expired.
    func getEpisodes(for podcastId: UUID) -> [Episode]? {
        let fileURL = cacheURL(for: podcastId)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let cacheEntry = try JSONDecoder().decode(CacheEntry.self, from: data)
            
            if cacheEntry.isExpired {
                // Delete the expired cache file
                try? fileManager.removeItem(at: fileURL)
                return nil
            } else {
                return cacheEntry.episodes
            }
        } catch {
            return nil
        }
    }
    
    /// Retrieves all episodes from the cache.
    func getAllEpisodes() -> [Episode] {
        var allEpisodes: [Episode] = []
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for fileURL in contents {
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                let cacheEntry = try? JSONDecoder().decode(CacheEntry.self, from: data)
                if let episodes = cacheEntry?.episodes {
                    allEpisodes.append(contentsOf: episodes)
                }
            }
            return allEpisodes
        } catch {
            return []
        }
    }
    
    /// Saves episodes to the cache for a given podcast ID.
    /// - Parameters:
    ///   - episodes: The array of `Episode` objects to cache.
    ///   - podcastId: The `UUID` of the podcast.
    func saveEpisodes(_ episodes: [Episode], for podcastId: UUID) {
        let entry = CacheEntry(episodes: episodes)
        let fileURL = cacheURL(for: podcastId)
        
        do {
            let data = try JSONEncoder().encode(entry)
            try data.write(to: fileURL, options: .atomic)
            
            // Check cache size and cleanup if needed
            checkCacheSizeAndCleanup()
        } catch {
            // Silent failure - cache is non-critical
        }
    }
    
    /// Removes the cached episodes for a specific podcast ID.
    /// - Parameter podcastId: The `UUID` of the podcast to remove from the cache.
    func clearCache(for podcastId: UUID) {
        let fileURL = cacheURL(for: podcastId)
        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }
    }
    
    /// Clears the entire episode cache directory.
    func clearAllCache() {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for fileURL in contents {
                try fileManager.removeItem(at: fileURL)
            }
        } catch {
            // Silent failure
        }
    }
    
    // MARK: - Private Helpers
    
    private func cacheURL(for podcastId: UUID) -> URL {
        return cacheDirectory.appendingPathComponent("\(podcastId.uuidString).json")
    }
    
    /// Check cache size and cleanup old entries if needed
    private func checkCacheSizeAndCleanup() {
        do {
            let cacheFiles = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            
            // Calculate total cache size
            let totalSize = cacheFiles.reduce(0) { total, fileURL in
                let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return total + fileSize
            }
            
            // If cache is too large, remove oldest files
            if totalSize > Config.maxCacheSize {
                // Sort files by modification date (oldest first)
                let sortedFiles = cacheFiles.sorted { file1, file2 in
                    let date1 = (try? file1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                    let date2 = (try? file2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                    return date1 < date2
                }
                
                // Remove oldest files until we're under the limit
                var currentSize = totalSize
                for fileURL in sortedFiles {
                    if currentSize <= Config.maxCacheSize / 2 { // Clean to 50% of limit
                        break
                    }
                    
                    let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    try? fileManager.removeItem(at: fileURL)
                    currentSize -= fileSize
                }
            }
        } catch {
            // Silent failure
        }
    }
    
    /// Represents a single entry in the cache.
    private struct CacheEntry: Codable {
        let episodes: [Episode]
        let timestamp: Date
        
        // Cache expires after configured interval
        private static let expirationInterval: TimeInterval = Config.cacheExpirationInterval
        
        var isExpired: Bool {
            return Date().timeIntervalSince(timestamp) > Self.expirationInterval
        }
        
        init(episodes: [Episode]) {
            self.episodes = episodes
            self.timestamp = Date()
        }
    }
}