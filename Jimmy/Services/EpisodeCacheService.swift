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
            // Use the enhanced error handling method
            PodcastService.shared.fetchEpisodesWithError(for: podcast) { episodes, error in
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
                    // Generate specific error message based on the error type
                    let errorMessage: String
                    if let error = error {
                        errorMessage = self.generateNetworkErrorMessage(for: error, podcast: podcast)
                        
                        #if canImport(OSLog)
                        self.logger.error("Network error for \(podcast.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        #else
                        print("❌ Network error for \(podcast.title): \(error.localizedDescription)")
                        #endif
                    } else {
                        errorMessage = self.generateErrorMessage(for: podcast)
                        
                        #if canImport(OSLog)
                        self.logger.warning("No episodes found for \(podcast.title, privacy: .public), not caching empty result.")
                        #else
                        print("⚠️ No episodes found for \(podcast.title), not caching empty result.")
                        #endif
                    }
                    
                    completion([], errorMessage)
                }
            }
        }
    }
    
    /// Fetch and cache episodes progressively, updating UI as episodes are parsed
    /// - Parameters:
    ///   - podcast: The podcast to fetch episodes for
    ///   - progressCallback: Called for each episode as it's parsed (on main queue)
    ///   - completion: Called when all episodes are fetched and cached
    private func fetchAndCacheEpisodesProgressively(for podcast: Podcast, 
                                                   progressCallback: @escaping (Episode) -> Void,
                                                   completion: @escaping ([Episode], String?) -> Void) {
        
        #if canImport(OSLog)
        logger.info("Starting progressive fetch for \(podcast.title, privacy: .public)")
        #else
        print("🚀 Starting progressive fetch for \(podcast.title)")
        #endif
        
        var allEpisodes: [Episode] = []
        
        PodcastService.shared.fetchEpisodesProgressively(
            for: podcast,
            episodeCallback: { episode in
                // Add episode to our collection
                allEpisodes.append(episode)
                
                // Update UI immediately
                progressCallback(episode)
                
                // Cache episodes in batches for better performance
                if allEpisodes.count % 10 == 0 {
                    Task { [weak self] in
                        await self?.cacheEpisodesAsync(allEpisodes, for: podcast.id)
                    }
                }
            },
            metadataCallback: { metadata in
                // Metadata callback - could be used to update podcast info
                #if canImport(OSLog)
                self.logger.info("Received metadata for \(podcast.title, privacy: .public): \(metadata.title ?? "Unknown", privacy: .public)")
                #else
                print("📊 Received metadata for \(podcast.title): \(metadata.title ?? "Unknown")")
                #endif
            },
            completion: { episodes, error in
                if !episodes.isEmpty {
                    // Final cache of all episodes
                    Task { [weak self] in
                        await self?.cacheEpisodesAsync(episodes, for: podcast.id)
                        
                        #if canImport(OSLog)
                        self?.logger.info("Progressive fetch completed and cached \(episodes.count) episodes for \(podcast.title, privacy: .public)")
                        #else
                        print("💾 Progressive fetch completed and cached \(episodes.count) episodes for \(podcast.title)")
                        #endif
                    }
                    
                    completion(episodes, nil)
                } else {
                    // Generate specific error message based on the error type
                    let errorMessage: String
                    if let error = error {
                        errorMessage = self.generateNetworkErrorMessage(for: error, podcast: podcast)
                        
                        #if canImport(OSLog)
                        self.logger.error("Progressive fetch error for \(podcast.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        #else
                        print("❌ Progressive fetch error for \(podcast.title): \(error.localizedDescription)")
                        #endif
                    } else {
                        errorMessage = self.generateErrorMessage(for: podcast)
                        
                        #if canImport(OSLog)
                        self.logger.warning("Progressive fetch found no episodes for \(podcast.title, privacy: .public)")
                        #else
                        print("⚠️ Progressive fetch found no episodes for \(podcast.title)")
                        #endif
                    }
                    
                    completion([], errorMessage)
                }
            }
        )
    }
    
    /// Async version of cacheEpisodes for better performance
    private func cacheEpisodesAsync(_ episodes: [Episode], for podcastID: UUID) async {
        await withCheckedContinuation { continuation in
            cacheQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else { 
                    continuation.resume()
                    return 
                }
                
                let entry = CacheEntry(
                    episodes: episodes,
                    timestamp: Date(),
                    lastModified: nil
                )
                
                self.episodeCache[podcastID] = entry
                
                // Manage cache size to prevent memory issues
                self.manageCacheSize()
                
                continuation.resume()
            }
            
            // Save to disk asynchronously
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.saveCacheToDisk()
            }
        }
    }
    
    /// Generate specific error message based on network error type
    private func generateNetworkErrorMessage(for error: Error, podcast: Podcast) -> String {
        let nsError = error as NSError
        
        switch nsError.code {
        case NSURLErrorTimedOut:
            return "Connection timed out. The podcast server is taking too long to respond. Please try again."
            
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
            return "Cannot connect to the podcast server. The server may be temporarily unavailable."
            
        case NSURLErrorNetworkConnectionLost:
            return "Network connection was lost. Please check your internet connection and try again."
            
        case NSURLErrorDNSLookupFailed:
            return "Cannot find the podcast server. The podcast may have moved or the URL may be incorrect."
            
        case NSURLErrorNotConnectedToInternet:
            return "No internet connection. Please connect to Wi-Fi or cellular data and try again."
            
        case NSURLErrorInternationalRoamingOff:
            return "International roaming is disabled. Please enable roaming or connect to Wi-Fi."
            
        case NSURLErrorDataNotAllowed:
            return "Cellular data is disabled for this app. Please enable cellular data or connect to Wi-Fi."
            
        case NSURLErrorBadURL:
            return "The podcast feed URL is invalid. This podcast may have moved or been discontinued."
            
        case NSURLErrorHTTPTooManyRedirects:
            return "Too many redirects. The podcast feed configuration may be incorrect."
            
        case NSURLErrorResourceUnavailable:
            return "The podcast feed is currently unavailable. Please try again later."
            
        case NSURLErrorBadServerResponse:
            return "The podcast server returned an invalid response. The feed may be corrupted or temporarily unavailable."
            
        default:
            // Check for HTTP status codes in the error
            if let httpResponse = nsError.userInfo["NSHTTPURLResponse"] as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 400...499:
                    return "The podcast feed returned a client error (\(httpResponse.statusCode)). The podcast may have moved or been discontinued."
                case 500...599:
                    return "The podcast server is experiencing issues (\(httpResponse.statusCode)). Please try again later."
                default:
                    break
                }
            }
            
            // Fallback to generic network error message
            return "Network error: \(error.localizedDescription). Please check your connection and try again."
        }
    }
    
    private func generateErrorMessage(for podcast: Podcast) -> String {
        // Check if the feed URL looks suspicious or might be invalid
        let feedURLString = podcast.feedURL.absoluteString.lowercased()
        
        // Check network connectivity first
        if !NetworkMonitor.shared.isConnected {
            return "No internet connection. Please check your network settings and try again."
        }
        
        if feedURLString.contains("itunes.apple.com") || feedURLString.contains("podcasts.apple.com") {
            return "This podcast may only be available on Apple Podcasts. Try searching for it in the Apple Podcasts app."
        } else if feedURLString.contains("spotify.com") {
            return "This podcast may only be available on Spotify. Try searching for it in the Spotify app."
        } else if feedURLString.contains("youtube.com") {
            return "This podcast may only be available on YouTube. Try searching for it in the YouTube app."
        } else if !feedURLString.contains("rss") && !feedURLString.contains("feed") && !feedURLString.contains(".xml") {
            return "The podcast feed URL appears to be invalid. This podcast may not have a public RSS feed."
        } else {
            // Provide more specific network-related error messages
            return "Unable to load episodes. This could be due to:\n\n• Temporary network connectivity issues\n• The podcast feed server is temporarily unavailable\n• The podcast may have moved to a different platform\n\nPlease try again in a few moments."
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
            
            let _ = self.episodeCache.count
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

    /// Manually retry fetching episodes for a podcast (useful for error recovery)
    /// - Parameters:
    ///   - podcast: The podcast to retry fetching for
    ///   - completion: Completion handler with episodes and optional error message
    func retryFetchingEpisodes(for podcast: Podcast, completion: @escaping ([Episode], String?) -> Void) {
        let podcastID = podcast.id
        
        // Clear any existing error state
        Task { @MainActor in
            self.loadingErrors.removeValue(forKey: podcastID)
            self.isLoadingEpisodes[podcastID] = true
        }
        
        #if canImport(OSLog)
        logger.info("Manually retrying episode fetch for \(podcast.title, privacy: .public)")
        #else
        print("🔄 Manually retrying episode fetch for \(podcast.title)")
        #endif
        
        // Force a fresh fetch (bypass cache)
        fetchAndCacheEpisodes(for: podcast) { episodes, error in
            Task { @MainActor in
                self.isLoadingEpisodes[podcastID] = false
                
                if let error = error {
                    self.loadingErrors[podcastID] = error
                }
                
                completion(episodes, error)
            }
        }
    }
    
    /// Check if a podcast has a loading error
    /// - Parameter podcastID: The podcast ID to check
    /// - Returns: The error message if there is one, nil otherwise
    func getLoadingError(for podcastID: UUID) -> String? {
        return loadingErrors[podcastID]
    }
    
    /// Clear loading error for a specific podcast
    /// - Parameter podcastID: The podcast ID to clear error for
    func clearLoadingError(for podcastID: UUID) {
        Task { @MainActor in
            loadingErrors.removeValue(forKey: podcastID)
        }
    }

    /// Load episodes for a podcast with progressive UI updates using thread-safe architecture
    /// - Parameters:
    ///   - podcast: The podcast to load episodes for
    ///   - forceRefresh: Whether to bypass cache and fetch fresh data
    ///   - progressCallback: Called for each episode as it's parsed (on main queue)
    ///   - completion: Called when loading is complete with all episodes
    func loadEpisodesProgressively(for podcast: Podcast, 
                                  forceRefresh: Bool = false,
                                  progressCallback: @escaping (Episode) -> Void,
                                  completion: @escaping ([Episode]) -> Void) {
        let podcastID = podcast.id
        let operationId = "load-episodes-progressive-\(podcastID)"
        
        // Ensure cache is loaded before proceeding
        if !self.isCacheLoaded {
            self.loadCacheFromDisk()
        }
        
        // Proceed with progressive loading
        Task { [weak self] in
            guard let self = self else { 
                completion([])
                return 
            }
            
            // Use DataFetchCoordinator for thread-safe operation
            DataFetchCoordinator.shared.startFetch(
                id: operationId,
                operation: {
                    // This runs on background thread
                    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Episode], Error>) in
                        
                        // Set up a timeout to prevent continuation leaks
                        let timeoutTask = Task {
                            try await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
                            Task { @MainActor in
                                self.isLoadingEpisodes[podcastID] = false
                            }
                            continuation.resume(throwing: NSError(domain: "EpisodeCacheService", code: 408, userInfo: [
                                NSLocalizedDescriptionKey: "Episode loading timed out",
                                NSLocalizedRecoverySuggestionErrorKey: "The podcast feed took too long to load. Please try again."
                            ]))
                        }
                        
                        // Check if already loading (thread-safe)
                        Task { @MainActor in
                            if self.isLoadingEpisodes[podcastID] == true {
                                #if canImport(OSLog)
                                self.logger.info("Already loading episodes for \(podcast.title, privacy: .public), skipping duplicate request")
                                #else
                                print("⏳ Already loading episodes for \(podcast.title), skipping duplicate request")
                                #endif
                                timeoutTask.cancel()
                                continuation.resume(returning: [])
                                return
                            }
                            
                            self.isLoadingEpisodes[podcastID] = true
                        }
                        
                        // Check cache first (unless force refresh)
                        if !forceRefresh {
                            self.getCachedEpisodesAsync(for: podcastID) { cachedEpisodes in
                                if let episodes = cachedEpisodes {
                                    #if canImport(OSLog)
                                    self.logger.info("Using cached episodes for \(podcast.title, privacy: .public)")
                                    #else
                                    print("💾 Using cached episodes for \(podcast.title)")
                                    #endif
                                    
                                    Task { @MainActor in
                                        self.isLoadingEpisodes[podcastID] = false
                                        
                                        // Send cached episodes progressively for immediate UI update
                                        for episode in episodes {
                                            progressCallback(episode)
                                            
                                            // Notify UIUpdateService on main actor
                                            Task { @MainActor in
                                                UIUpdateService.shared.handleProgressiveEpisodeUpdate(
                                                    podcastId: podcastID,
                                                    episode: episode
                                                )
                                            }
                                        }
                                        
                                        timeoutTask.cancel()
                                        continuation.resume(returning: episodes)
                                    }
                                } else {
                                    // No cache available - proceed with progressive network fetch
                                    self.performThreadSafeProgressiveFetch(
                                        for: podcast,
                                        forceRefresh: forceRefresh,
                                        progressCallback: progressCallback,
                                        continuation: continuation,
                                        timeoutTask: timeoutTask
                                    )
                                }
                            }
                        } else {
                            // Force refresh - skip cache and fetch progressively from network
                            self.performThreadSafeProgressiveFetch(
                                for: podcast,
                                forceRefresh: forceRefresh,
                                progressCallback: progressCallback,
                                continuation: continuation,
                                timeoutTask: timeoutTask
                            )
                        }
                    }
                },
                onComplete: { result in
                    // This runs on main thread
                    switch result {
                    case .success(let episodes):
                        completion(episodes)
                        
                    case .failure(let error):
                        #if canImport(OSLog)
                        self.logger.error("Progressive episode loading failed for \(podcast.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        #else
                        print("❌ Progressive episode loading failed for \(podcast.title): \(error.localizedDescription)")
                        #endif
                        
                        Task { @MainActor in
                            self.isLoadingEpisodes[podcastID] = false
                            self.loadingErrors[podcastID] = error.localizedDescription
                        }
                        
                        completion([])
                    }
                }
            )
        }
    }
    
    /// Perform thread-safe progressive fetch using the new architecture
    private func performThreadSafeProgressiveFetch(
        for podcast: Podcast,
        forceRefresh: Bool,
        progressCallback: @escaping (Episode) -> Void,
        continuation: CheckedContinuation<[Episode], Error>,
        timeoutTask: Task<Void, Error>
    ) {
        let podcastID = podcast.id
        
        // Check network connectivity
        if !NetworkMonitor.shared.isConnected {
            getCachedEpisodesAsync(for: podcastID, ignoreExpiry: true) { offlineCachedEpisodes in
                if let episodes = offlineCachedEpisodes {
                    #if canImport(OSLog)
                    self.logger.info("Offline - using cached episodes for \(podcast.title, privacy: .public)")
                    #else
                    print("📡 Offline - using cached episodes for \(podcast.title)")
                    #endif
                    
                    Task { @MainActor in
                        self.isLoadingEpisodes[podcastID] = false
                        self.loadingErrors[podcastID] = "You appear to be offline. Showing cached episodes."
                        
                        // Send cached episodes progressively
                        for episode in episodes {
                            progressCallback(episode)
                            
                            // Notify UIUpdateService on main actor
                            Task { @MainActor in
                                UIUpdateService.shared.handleProgressiveEpisodeUpdate(
                                    podcastId: podcastID,
                                    episode: episode
                                )
                            }
                        }
                        
                        timeoutTask.cancel()
                        continuation.resume(returning: episodes)
                    }
                } else {
                    Task { @MainActor in
                        self.isLoadingEpisodes[podcastID] = false
                        self.loadingErrors[podcastID] = "You appear to be offline."
                    }
                    timeoutTask.cancel()
                    continuation.resume(throwing: NetworkError.offline)
                }
            }
            return
        }
        
        // Fetch fresh data progressively using thread-safe service
        #if canImport(OSLog)
        logger.info("Fetching fresh episodes progressively for \(podcast.title, privacy: .public) (force: \(forceRefresh))")
        #else
        print("🌐 Fetching fresh episodes progressively for \(podcast.title) (force: \(forceRefresh))")
        #endif
        
        var allEpisodes: [Episode] = []
        
        PodcastService.shared.fetchEpisodesProgressively(
            for: podcast,
            episodeCallback: { episode in
                // This is called on main thread
                allEpisodes.append(episode)
                
                // Update UI immediately
                progressCallback(episode)
                
                // Cache episodes in batches for better performance
                if allEpisodes.count % 10 == 0 {
                    Task { [weak self] in
                        await self?.cacheEpisodesAsync(allEpisodes, for: podcast.id)
                    }
                }
            },
            metadataCallback: { metadata in
                // This is called on main thread
                #if canImport(OSLog)
                self.logger.info("Received metadata for \(podcast.title, privacy: .public): \(metadata.title ?? "Unknown", privacy: .public)")
                #else
                print("📊 Received metadata for \(podcast.title): \(metadata.title ?? "Unknown")")
                #endif
            },
            completion: { episodes, error in
                // This is called on main thread
                Task { @MainActor in
                    self.isLoadingEpisodes[podcastID] = false
                    
                    if let error = error {
                        let errorMessage = self.generateNetworkErrorMessage(for: error, podcast: podcast)
                        self.loadingErrors[podcastID] = errorMessage
                        
                        // If we have stale cache data, return it as fallback
                        self.getCachedEpisodesAsync(for: podcastID, ignoreExpiry: true) { staleEpisodes in
                            if let episodes = staleEpisodes {
                                #if canImport(OSLog)
                                self.logger.warning("Using stale cache as fallback for \(podcast.title, privacy: .public)")
                                #else
                                print("⚠️ Using stale cache as fallback for \(podcast.title)")
                                #endif
                                
                                // Send stale episodes progressively
                                for episode in episodes {
                                    progressCallback(episode)
                                    
                                    // Notify UIUpdateService on main actor
                                    Task { @MainActor in
                                        UIUpdateService.shared.handleProgressiveEpisodeUpdate(
                                            podcastId: podcastID,
                                            episode: episode
                                        )
                                    }
                                }
                                
                                timeoutTask.cancel()
                                continuation.resume(returning: episodes)
                            } else {
                                timeoutTask.cancel()
                                continuation.resume(throwing: error)
                            }
                        }
                    } else {
                        self.loadingErrors[podcastID] = nil
                        
                        // Final cache of all episodes
                        Task { [weak self] in
                            await self?.cacheEpisodesAsync(episodes, for: podcast.id)
                            
                            #if canImport(OSLog)
                            self?.logger.info("Progressive fetch completed and cached \(episodes.count) episodes for \(podcast.title, privacy: .public)")
                            #else
                            print("💾 Progressive fetch completed and cached \(episodes.count) episodes for \(podcast.title)")
                            #endif
                        }
                        
                        timeoutTask.cancel()
                        continuation.resume(returning: episodes)
                    }
                }
            }
        )
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