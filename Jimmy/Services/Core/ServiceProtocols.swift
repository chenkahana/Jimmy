import Foundation
import Combine

// MARK: - Core Service Protocols
// Defines clean interfaces for all major services to reduce coupling

// MARK: - Service Lifecycle Protocol
protocol ServiceLifecycleProtocol {
    func initialize() async throws
    func shutdown() async
    var isReady: Bool { get }
}

// MARK: - Cache Service Protocol
protocol CacheServiceProtocol {
    associatedtype CacheKey: Hashable
    associatedtype CacheValue
    
    func get(key: CacheKey) async -> CacheValue?
    func set(key: CacheKey, value: CacheValue) async
    func remove(key: CacheKey) async
    func clear() async
}

// MARK: - Network Service Protocol
protocol NetworkServiceProtocol {
    func fetchData(from url: URL) async throws -> Data
    func fetchDataWithHeaders(url: URL, etag: String?, lastModified: String?) async throws -> (Data, String?, String?)
    func head(url: URL) async throws -> HTTPURLResponse
}

// MARK: - Parsing Service Protocol
protocol ParsingServiceProtocol {
    associatedtype ParsedResult
    
    func parse(data: Data) async throws -> ParsedResult
    func canParse(data: Data) -> Bool
}

// MARK: - Data Service Protocol
protocol DataServiceProtocol {
    associatedtype Entity
    associatedtype EntityID: Hashable
    
    func fetch(id: EntityID) async throws -> Entity?
    func fetchAll() async throws -> [Entity]
    func save(_ entity: Entity) async throws
    func delete(id: EntityID) async throws
}

// MARK: - Podcast Service Protocols
protocol PodcastDataServiceProtocol: DataServiceProtocol where Entity == Podcast, EntityID == UUID {
    func fetchPodcasts(ignoreCache: Bool) async throws -> [Podcast]
    func addPodcast(from feedURL: URL) async throws -> (Podcast, [Episode])
    func updatePodcast(_ podcast: Podcast) async throws
    func deletePodcast(id: UUID) async throws
}

protocol PodcastDiscoveryServiceProtocol {
    func searchPodcasts(query: String) async throws -> [Podcast]
    func getTrendingPodcasts() async throws -> [Podcast]
    func getRecommendations() async throws -> [Podcast]
}

protocol PodcastSubscriptionServiceProtocol {
    func subscribe(to feedURL: URL) async throws -> (Podcast, [Episode])
    func unsubscribe(from podcastID: UUID) async throws
    func isSubscribed(to podcastID: UUID) async -> Bool
    func getSubscriptions() async throws -> [Podcast]
}

// MARK: - Episode Service Protocols
protocol EpisodeDataServiceProtocol: DataServiceProtocol where Entity == Episode, EntityID == UUID {
    func fetchEpisodes(for podcastID: UUID, limit: Int?, cursor: String?) async throws -> ([Episode], String?)
    func markAsPlayed(_ episodeID: UUID) async throws
    func updatePlaybackPosition(_ episodeID: UUID, position: TimeInterval) async throws
}

protocol EpisodePlaybackServiceProtocol {
    func play(_ episode: Episode) async throws
    func pause() async
    func stop() async
    func seek(to position: TimeInterval) async
    var currentEpisode: Episode? { get }
    var isPlaying: Bool { get }
    var playbackPosition: TimeInterval { get }
}

protocol EpisodeCacheServiceProtocol: CacheServiceProtocol where CacheKey == UUID, CacheValue == Episode {
    func cacheEpisodes(_ episodes: [Episode]) async
    func getCachedEpisodes(for podcastID: UUID) async -> [Episode]
    func clearCache(for podcastID: UUID) async
}

// MARK: - Service Configuration
struct ServiceConfiguration {
    let maxConcurrentOperations: Int
    let timeoutInterval: TimeInterval
    let retryAttempts: Int
    let cacheSize: Int
    
    static let `default` = ServiceConfiguration(
        maxConcurrentOperations: 4,
        timeoutInterval: 30.0,
        retryAttempts: 3,
        cacheSize: 100
    )
}

// MARK: - Service Registry Protocol
protocol ServiceRegistryProtocol {
    func register<T>(_ service: T, for type: T.Type)
    func resolve<T>(_ type: T.Type) -> T?
    func unregister<T>(_ type: T.Type)
}