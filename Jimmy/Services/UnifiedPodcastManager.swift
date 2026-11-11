import Foundation
import Combine
import OSLog

/// PERF-09: Unified Podcast Manager - Phase 1 of Service Consolidation
///
/// This facade provides a unified interface to podcast-related services:
/// - PodcastEngine (streaming and performance)
/// - PodcastService (data persistence via DIContainer)
/// - WorldClassIntegration (caching and optimization)
///
/// Benefits:
/// - Single entry point for podcast operations
/// - Consistent error handling and logging
/// - Easier testing and maintenance
/// - Foundation for future service consolidation
@MainActor
final class UnifiedPodcastManager: ObservableObject {
    static let shared = UnifiedPodcastManager()
    
    private let logger = Logger(subsystem: "Jimmy.UnifiedPodcast", category: "Manager")
    
    // MARK: - Underlying Services (will be consolidated in future phases)
    private let podcastEngine = PodcastEngine.shared
    
    // MARK: - Published State
    @Published private(set) var podcasts: [Podcast] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: Error?
    
    // MARK: - Initialization
    
    private init() {
        logger.info("🎙️ UnifiedPodcastManager initialized")
    }
    
    // MARK: - Public API
    
    /// Fetch all podcasts with intelligent caching
    /// - Parameters:
    ///   - forceRefresh: If true, bypass cache and fetch from network
    ///   - progressHandler: Optional handler for progressive loading updates
    /// - Returns: Array of podcasts
    func fetchPodcasts(
        forceRefresh: Bool = false,
        progressHandler: ((Podcast, Int) -> Void)? = nil
    ) async throws -> [Podcast] {
        isLoading = true
        lastError = nil
        
        defer { isLoading = false }
        
        do {
            if let handler = progressHandler {
                // Use streaming approach for progressive updates
                try await podcastEngine.streamPodcasts(
                    forceRefresh: forceRefresh,
                    progressHandler: handler
                )
                return podcasts
            } else {
                // Use batch approach
                let enhanced = try await podcastEngine.fetchPodcasts(forceRefresh: forceRefresh)
                let result = enhanced.map { $0.basePodcast }
                podcasts = result
                return result
            }
        } catch {
            lastError = error
            logger.error("❌ Failed to fetch podcasts: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Subscribe to a new podcast
    /// - Parameter feedURL: The RSS feed URL to subscribe to
    /// - Returns: Tuple of the new podcast and its episodes
    func subscribe(to feedURL: URL) async throws -> (Podcast, [Episode]) {
        isLoading = true
        lastError = nil
        
        defer { isLoading = false }
        
        do {
            let (enhanced, episodes) = try await podcastEngine.subscribe(to: feedURL)
            let podcast = enhanced.basePodcast
            
            logger.info("✅ Subscribed to '\(podcast.title)'")
            return (podcast, episodes)
        } catch {
            lastError = error
            logger.error("❌ Failed to subscribe: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Get a specific podcast by ID
    /// - Parameter id: The podcast ID
    /// - Returns: The podcast if found
    func getPodcast(id: UUID) async -> Podcast? {
        return podcasts.first { $0.id == id }
    }
    
    /// Refresh a specific podcast
    /// - Parameter podcast: The podcast to refresh
    /// - Returns: Updated podcast with latest data
    func refresh(podcast: Podcast) async throws -> (Podcast, [Episode]) {
        do {
            let enhanced = try await podcastEngine.fetchPodcasts(forceRefresh: true)
            if let updated = enhanced.first(where: { $0.id == podcast.id }) {
                let episodes = try await podcastEngine.fetchEpisodes(for: updated)
                return (updated.basePodcast, episodes)
            }
            return (podcast, [])
        } catch {
            lastError = error
            logger.error("❌ Failed to refresh podcast: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Sorting
    
    /// Sort podcasts by the specified criteria
    /// - Parameters:
    ///   - podcasts: Podcasts to sort
    ///   - sortType: How to sort the podcasts
    /// - Returns: Sorted array of podcasts
    func sort(_ podcasts: [Podcast], by sortType: SortType) -> [Podcast] {
        switch sortType {
        case .alphabetical:
            return podcasts.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .latestEpisode:
            return podcasts.sorted { ($0.lastEpisodeDate ?? .distantPast) > ($1.lastEpisodeDate ?? .distantPast) }
        case .subscriptionDate:
            return podcasts.sorted { ($0.lastFetched ?? .distantPast) > ($1.lastFetched ?? .distantPast) }
        default:
            return podcasts
        }
    }
    
    // MARK: - Diagnostics
    
    /// Get diagnostic information about the manager
    func getDiagnostics() -> [String: Any] {
        return [
            "podcastCount": podcasts.count,
            "isLoading": isLoading,
            "hasError": lastError != nil,
            "engineStatus": String(describing: podcastEngine.engineStatus)
        ]
    }
}
