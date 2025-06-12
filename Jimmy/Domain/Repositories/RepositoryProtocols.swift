import Foundation
import Combine

// MARK: - Repository Protocols
// Define clean interfaces for data access without implementation details

/// Protocol for podcast data operations
protocol PodcastRepositoryProtocol {
    /// Fetch all subscribed podcasts
    func fetchPodcasts() async throws -> [Podcast]
    
    /// Fetch a single podcast with its episodes from RSS feed
    func fetchPodcastWithEpisodes(from feedURL: URL) async throws -> (Podcast, [Episode])
    
    /// Save podcasts to persistent storage
    func savePodcasts(_ podcasts: [Podcast]) async throws
    
    /// Delete podcast data
    func deletePodcastData(id: UUID) async throws
    
    /// Publisher for podcast changes
    var podcastChangesPublisher: AnyPublisher<PodcastChanges, Never> { get }
}

/// Protocol for episode data operations
protocol EpisodeRepositoryProtocol {
    /// Fetch episodes for a specific podcast
    func fetchEpisodes(for podcastID: UUID) async throws -> [Episode]
    
    /// Fetch all episodes
    func fetchAllEpisodes() async throws -> [Episode]
    
    /// Save episodes to persistent storage
    func saveEpisodes(_ episodes: [Episode]) async throws
    
    /// Delete episodes for a podcast
    func deleteEpisodes(forPodcastID podcastID: UUID) async throws
    
    /// Publisher for episode changes
    var episodeChangesPublisher: AnyPublisher<CleanEpisodeChanges, Never> { get }
}

/// Protocol for network operations
protocol NetworkRepositoryProtocol {
    /// Fetch RSS feed data
    func fetchRSSFeed(from url: URL) async throws -> Data
    
    /// Download episode audio
    func downloadEpisodeAudio(from url: URL) async throws -> URL
    
    /// Check network connectivity
    var isConnected: Bool { get async }
}

/// Protocol for local storage operations
protocol StorageRepositoryProtocol {
    /// Save data to local storage
    func save<T: Codable>(_ data: T, to key: String) async throws
    
    /// Load data from local storage
    func load<T: Codable>(_ type: T.Type, from key: String) async throws -> T?
    
    /// Delete data from local storage
    func delete(key: String) async throws
    
    /// Check if data exists
    func exists(key: String) async -> Bool
} 