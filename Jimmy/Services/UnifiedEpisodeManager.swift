import Foundation
import Combine
import OSLog

/// PERF-09: Unified Episode Manager - Phase 1 of Service Consolidation
///
/// This facade provides a unified interface to episode-related services:
/// - EpisodeService (fetching and pagination)
/// - StreamingEpisodeService (streaming parsing)
/// - EpisodeUpdateService (background updates)
/// - EpisodeCacheService (caching)
///
/// Benefits:
/// - Single entry point for episode operations
/// - Consistent error handling and logging
/// - Easier testing and maintenance
/// - Foundation for future service consolidation
@MainActor
final class UnifiedEpisodeManager: ObservableObject {
    static let shared = UnifiedEpisodeManager()
    
    private let logger = Logger(subsystem: "Jimmy.UnifiedEpisode", category: "Manager")
    
    // MARK: - Underlying Services (will be consolidated in future phases)
    private let streamingService = StreamingEpisodeService.shared
    private let updateService = EpisodeUpdateService.shared
    
    // MARK: - Published State
    @Published private(set) var episodesByPodcast: [UUID: [Episode]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: Error?
    
    // MARK: - Initialization
    
    private init() {
        logger.info("📻 UnifiedEpisodeManager initialized")
    }
    
    // MARK: - Public API
    
    /// Fetch episodes for a podcast with intelligent caching
    /// - Parameters:
    ///   - podcastID: The podcast's UUID
    ///   - feedURL: The RSS feed URL
    ///   - forceRefresh: If true, bypass cache and fetch from network
    ///   - progressHandler: Optional handler for progressive loading updates
    /// - Returns: Array of episodes
    func fetchEpisodes(
        for podcastID: UUID,
        feedURL: URL,
        forceRefresh: Bool = false,
        progressHandler: ((Episode, Int) -> Void)? = nil
    ) async throws -> [Episode] {
        isLoading = true
        lastError = nil
        
        defer { isLoading = false }
        
        do {
            // Check cache first unless force refresh
            if !forceRefresh {
                if let cached = await EpisodeCacheService.shared.getEpisodes(for: podcastID) {
                    episodesByPodcast[podcastID] = cached
                    logger.debug("⚡ Cache hit for podcast \(podcastID)")
                    return cached
                }
            }
            
            // Fetch from network with streaming
            let result = try await streamingService.fetchAllEpisodes(
                from: feedURL,
                podcastID: podcastID,
                timeout: 60.0,
                progressHandler: progressHandler
            )
            
            // Update cache
            await EpisodeCacheService.shared.saveEpisodes(result.episodes, for: podcastID)
            
            // Update state
            episodesByPodcast[podcastID] = result.episodes
            
            logger.info("✅ Fetched \(result.episodes.count) episodes for podcast")
            return result.episodes
        } catch {
            lastError = error
            logger.error("❌ Failed to fetch episodes: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Get episodes for a podcast from local cache
    /// - Parameter podcastID: The podcast's UUID
    /// - Returns: Cached episodes or nil
    func getCachedEpisodes(for podcastID: UUID) async -> [Episode]? {
        if let inMemory = episodesByPodcast[podcastID] {
            return inMemory
        }
        return await EpisodeCacheService.shared.getEpisodes(for: podcastID)
    }
    
    /// Clear cached episodes for a podcast
    /// - Parameter podcastID: The podcast's UUID
    func clearCache(for podcastID: UUID) async {
        episodesByPodcast.removeValue(forKey: podcastID)
        await EpisodeCacheService.shared.clearCache(for: podcastID)
        logger.debug("🗑️ Cleared cache for podcast \(podcastID)")
    }
    
    /// Clear all cached episodes
    func clearAllCache() async {
        episodesByPodcast.removeAll()
        await EpisodeCacheService.shared.clearAllCache()
        logger.debug("🗑️ Cleared all episode cache")
    }
    
    /// Trigger background episode update
    func triggerBackgroundUpdate() {
        updateService.forceUpdate()
        logger.debug("🔄 Triggered background episode update")
    }
    
    // MARK: - Diagnostics
    
    /// Get diagnostic information about the manager
    func getDiagnostics() -> [String: Any] {
        return [
            "cachedPodcastCount": episodesByPodcast.count,
            "totalCachedEpisodes": episodesByPodcast.values.reduce(0) { $0 + $1.count },
            "isLoading": isLoading,
            "hasError": lastError != nil
        ]
    }
}
