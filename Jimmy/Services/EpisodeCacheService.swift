import Foundation
import OSLog

/// A thread-safe, Codable-based cache for storing and retrieving podcast episodes.
final class EpisodeCacheService {
    static let shared = EpisodeCacheService()
    
    private let logger = Logger(subsystem: "com.jimmy.app", category: "episode-cache")
    private let fileManager = FileManager.default
    private let cacheQueue = DispatchQueue(label: "com.jimmy.episodeCacheQueue", attributes: .concurrent)
    
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
        logger.info("EpisodeCacheService initialized. Cache directory: \(self.cacheDirectory.path)")
    }
    
    // MARK: - Public API
    
    /// Asynchronously retrieves the cached episodes for a given podcast ID.
    /// - Parameter podcastId: The `UUID` of the podcast.
    /// - Returns: An array of `Episode` objects or `nil` if not found or expired.
    func getEpisodes(for podcastId: UUID) async -> [Episode]? {
        await withCheckedContinuation { continuation in
            cacheQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let fileURL = self.cacheURL(for: podcastId)
                
                guard self.fileManager.fileExists(atPath: fileURL.path) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                do {
                    let data = try Data(contentsOf: fileURL)
                    let cacheEntry = try JSONDecoder().decode(CacheEntry.self, from: data)
                    
                    if cacheEntry.isExpired {
                        self.logger.info("Cache expired for podcast \(podcastId.uuidString).")
                        // Optionally, delete the expired cache file
                        try? self.fileManager.removeItem(at: fileURL)
                        continuation.resume(returning: nil)
                    } else {
                        self.logger.info("Cache hit for podcast \(podcastId.uuidString). Returning \(cacheEntry.episodes.count) episodes.")
                        continuation.resume(returning: cacheEntry.episodes)
                    }
                } catch {
                    self.logger.error("Failed to read or decode cache for podcast \(podcastId.uuidString): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    /// Asynchronously saves episodes to the cache for a given podcast ID.
    /// - Parameters:
    ///   - episodes: The array of `Episode` objects to cache.
    ///   - podcastId: The `UUID` of the podcast.
    func saveEpisodes(_ episodes: [Episode], for podcastId: UUID) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cacheQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                let entry = CacheEntry(episodes: episodes)
                let fileURL = self.cacheURL(for: podcastId)
                
                do {
                    let data = try JSONEncoder().encode(entry)
                    try data.write(to: fileURL, options: .atomic)
                    self.logger.info("Successfully cached \(episodes.count) episodes for podcast \(podcastId.uuidString).")
                    
                    // Check cache size and cleanup if needed
                    self.checkCacheSizeAndCleanup()
                } catch {
                    self.logger.error("Failed to save cache for podcast \(podcastId.uuidString): \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }
    
    /// Asynchronously removes the cached episodes for a specific podcast ID.
    /// - Parameter podcastId: The `UUID` of the podcast to remove from the cache.
    func clearCache(for podcastId: UUID) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cacheQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                let fileURL = self.cacheURL(for: podcastId)
                if self.fileManager.fileExists(atPath: fileURL.path) {
                    do {
                        try self.fileManager.removeItem(at: fileURL)
                        self.logger.info("Cleared cache for podcast \(podcastId.uuidString).")
                    } catch {
                        self.logger.error("Failed to clear cache for podcast \(podcastId.uuidString): \(error.localizedDescription)")
                    }
                }
                continuation.resume()
            }
        }
    }
    
    /// Asynchronously clears the entire episode cache directory.
    func clearAllCache() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cacheQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                do {
                    let contents = try self.fileManager.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: nil)
                    for fileURL in contents {
                        try self.fileManager.removeItem(at: fileURL)
                    }
                    self.logger.info("Cleared all episode caches.")
                } catch {
                    self.logger.error("Failed to clear all episode caches: \(error.localizedDescription)")
                }
                continuation.resume()
            }
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
                logger.warning("Cache size (\(totalSize) bytes) exceeds limit (\(Config.maxCacheSize) bytes). Cleaning up...")
                
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
                    logger.info("Removed cache file: \(fileURL.lastPathComponent)")
                }
            }
        } catch {
            logger.error("Failed to check cache size: \(error.localizedDescription)")
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