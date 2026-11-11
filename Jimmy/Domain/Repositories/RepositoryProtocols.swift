import Foundation
import Combine
import GRDB

// MARK: - Repository Protocols
// Define clean interfaces for data access without implementation details.
// These protocols support a layered caching strategy (Memory -> Disk -> Network).

/// A generic repository protocol for entities conforming to Codable and Identifiable.
protocol Repository {
    associatedtype Entity: Codable, Identifiable
    
    func get(id: Entity.ID) async throws -> Entity?
    func getAll() async throws -> [Entity]
    func save(_ entity: Entity) async throws
    func saveAll(_ entities: [Entity]) async throws
    func delete(id: Entity.ID) async throws
}

/// Protocol for subscription data operations (user's podcast subscriptions)
protocol SubscriptionRepositoryProtocol {
    /// Fetch all user subscriptions with staleness check
    func fetchSubscriptions(ignoreCache: Bool) async throws -> [Podcast]
    
    /// Fetch a single subscription by ID with caching
    func fetchSubscription(id: UUID, ignoreCache: Bool) async throws -> Podcast?
    
    /// Add a new subscription
    func addSubscription(_ podcast: Podcast) async throws
    
    /// Remove a subscription
    func removeSubscription(id: UUID) async throws
    
    /// Remove all subscriptions (for database reset)
    func removeAllSubscriptions() async throws
    
    /// Update subscription settings
    func updateSubscription(_ podcast: Podcast) async throws
    
    /// Check if data is stale (24 hours for shows)
    func isStale(podcast: Podcast) -> Bool
    
    /// Publisher for subscription changes
    var subscriptionChangesPublisher: AnyPublisher<[Podcast], Never> { get }
}

/// Protocol for podcast data operations
protocol PodcastRepositoryProtocol {
    /// Fetch all subscribed podcasts
    func fetchPodcasts(ignoreCache: Bool) async throws -> [Podcast]
    
    /// Fetch a single podcast by ID
    func fetchPodcast(id: UUID, ignoreCache: Bool) async throws -> Podcast?
    
    /// Fetch a single podcast with its episodes from RSS feed
    func fetchPodcastWithEpisodes(from feedURL: URL) async throws -> (Podcast, [Episode])
    
    /// Fetch podcast data for preview only (without saving to database)
    func previewPodcastWithEpisodes(from feedURL: URL) async throws -> (Podcast, [Episode])
    
    /// Save podcasts to persistent storage
    func savePodcasts(_ podcasts: [Podcast]) async throws
    
    /// Add a single podcast
    func addPodcast(_ podcast: Podcast) async throws
    
    /// Update a single podcast
    func updatePodcast(_ podcast: Podcast) async throws
    
    /// Delete podcast data
    func deletePodcastData(id: UUID) async throws
    
    /// Publisher for podcast changes
    var podcastChangesPublisher: AnyPublisher<PodcastChanges, Never> { get }
}

/// Protocol for episode data operations with enhanced caching support
protocol EpisodeRepositoryProtocol {
    /// Fetch episodes for a specific podcast with pagination (cursor-based) and staleness check
    func fetchPage(podcastID: UUID, cursor: String?, limit: Int, ignoreCache: Bool) async throws -> ([EpisodeWithPlaybackState], nextCursor: String?)
    
    /// Phase 5: Fetch episodes with conditional GET support
    /// Returns nil if server responds with 304 Not Modified
    func fetchPageConditional(
        podcastID: UUID, 
        cursor: String?, 
        limit: Int, 
        etag: String?, 
        lastModified: String?
    ) async throws -> ([EpisodeWithPlaybackState], nextCursor: String?, newEtag: String?, newLastModified: String?)?
    
    /// Fetch episodes for a specific podcast with caching
    func fetchEpisodes(for podcastID: UUID, ignoreCache: Bool) async throws -> [EpisodeWithPlaybackState]
    
    /// Fetch all episodes for a specific podcast
    func fetchAllEpisodes(for podcastID: UUID, ignoreCache: Bool) async throws -> [EpisodeWithPlaybackState]
    
    /// Fetch a single episode by ID with its playback state
    func fetchEpisode(by episodeID: UUID) async throws -> EpisodeWithPlaybackState?
    
    /// Save episodes for a specific podcast with write-through caching
    func saveEpisodes(_ episodes: [EpisodeWithPlaybackState], for podcastID: UUID) async throws
    
    /// Check if episode data is stale (1 hour for episodes)
    func isStale(podcastID: UUID) -> Bool
    
    /// Publisher for episode changes
    var episodeChangesPublisher: AnyPublisher<CleanEpisodeChanges, Never> { get }
}

/// Protocol for show data operations with caching support
protocol ShowRepositoryProtocol {
    /// Fetch show metadata with caching
    func fetchShow(from feedURL: URL, ignoreCache: Bool) async throws -> ShowMetadata
    
    /// Check if show data is stale (24 hours for shows)
    func isStale(feedURL: URL) -> Bool
}

/// Protocol for playback state operations
protocol PlaybackStateRepositoryProtocol {
    /// Save the playback state for an episode.
    func savePlaybackState(_ state: PlaybackState) async throws
    
    /// Save multiple playback states in a batch.
    func savePlaybackStates(_ states: [PlaybackState]) async throws
    
    /// Fetch the playback state for an episode.
    func fetchPlaybackState(for episodeID: UUID) async throws -> PlaybackState?
    
    /// Mark an episode as finished (for swipe actions)
    func markFinished(episodeID: UUID) async throws
    
    /// Get episodes in queue order (queuePosition 1, 2, 3, etc.)
    func fetchQueuedEpisodes() async throws -> [EpisodeWithPlaybackState]
    
    /// Add episode to queue at specific position (1 = first)
    func addToQueue(episodeID: UUID, position: Int) async throws
    
    /// Remove episode from queue and reorder remaining episodes
    func removeFromQueue(episodeID: UUID) async throws
    
    /// Move episode to specific queue position and reorder others
    func moveInQueue(episodeID: UUID, toPosition: Int) async throws
    
    /// Get the next episode in queue (queuePosition = 1)
    func getNextQueuedEpisode() async throws -> EpisodeWithPlaybackState?
    
    /// Get the maximum queue position.
    func getMaxQueuePosition() async throws -> Int?
    
    /// Fetch all playback states (for progress cache pre-loading)
    func fetchAllPlaybackStates() async throws -> [PlaybackState]

    /// Reorder the entire queue to match the given episode ID order.
    /// Position 1 = first episode, position 2 = second, etc.
    /// Episodes not in the list are removed from the queue.
    func reorderQueue(episodeIDs: [UUID]) async throws
}

/// Protocol for the RSS parser.
protocol RSSParserProtocol {
    /// Parses RSS data and returns a tuple containing episodes and podcast metadata.
    func parse(data: Data, podcastID: UUID, feedURL: URL) async throws -> ([Episode], ShowMetadata)
}

/// Protocol for network operations with conditional GET support
protocol NetworkRepositoryProtocol {
    /// Fetch RSS feed data from URL
    func fetchRSSFeed(from url: URL, etag: String?, lastModified: Date?) async throws -> (Data, etag: String?, lastModified: String?)
    
    /// Phase 5: Fetch RSS feed with conditional GET support
    /// Returns nil data if server responds with 304 Not Modified
    func fetchRSSFeedConditional(from url: URL, etag: String?, lastModified: String?) async throws -> (Data?, etag: String?, lastModified: String?)
    
    /// Fetch data from URL with timeout
    func fetchData(from url: URL, timeout: TimeInterval) async throws -> Data
    
    /// Check if URL is reachable
    func isReachable(url: URL) async -> Bool
}

/// Protocol for search operations
protocol SearchRepositoryProtocol {
    func searchPodcasts(query: String) async throws -> [Podcast]
}

// MARK: - Supporting Types

/// Changes to podcast data for reactive updates
struct PodcastChanges {
    let added: [Podcast]
    let removed: [Podcast]
    let updated: [Podcast]
    
    var isEmpty: Bool {
        return added.isEmpty && removed.isEmpty && updated.isEmpty
    }
}

/// Changes to episode data for reactive updates
struct CleanEpisodeChanges {
    let podcastID: UUID
    let added: [EpisodeWithPlaybackState]
    let removed: [EpisodeWithPlaybackState]
    let updated: [EpisodeWithPlaybackState]
    
    var isEmpty: Bool {
        return added.isEmpty && removed.isEmpty && updated.isEmpty
    }
}

/// Podcast metadata from RSS parsing
struct ShowMetadata {
    let title: String?
    let author: String?
    let description: String?
    let artworkURL: URL?
    let language: String?
    let categories: [String]
}

/// Repository-specific errors
enum RepositoryError: Error, LocalizedError {
    case notFound
    case invalidData
    case networkUnavailable
    case cacheCorrupted
    case staleData
    case episodeAlreadyInQueue
    case invalidOperation
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Data not found"
        case .invalidData:
            return "Invalid data format"
        case .networkUnavailable:
            return "Network unavailable"
        case .cacheCorrupted:
            return "Cache data corrupted"
        case .staleData:
            return "Data is stale"
        case .episodeAlreadyInQueue:
            return "Episode is already in the queue"
        case .invalidOperation:
            return "Invalid queue operation"
        }
    }
}

/// Podcast repository specific errors
enum PodcastRepositoryError: Error, LocalizedError {
    case invalidRSSFeed
    case feedNotFound
    case parsingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidRSSFeed:
            return "Invalid RSS feed format"
        case .feedNotFound:
            return "RSS feed not found"
        case .parsingFailed:
            return "Failed to parse RSS feed"
        }
    }
} 