import Foundation

// MARK: - Dependency Injection Container
// Wires together all layers of the clean architecture

final class DIContainer {
    static let shared = DIContainer()

    // MARK: - Stores (Actors for thread safety)
    @MainActor lazy var progressCacheStore = ProgressCacheStore.shared
    
    // MARK: - Core Infrastructure
    lazy var databaseManager = DatabaseManager.shared
    lazy var memoryCacheStore = MemoryCacheStore.shared
    lazy var rssParser: RSSParserProtocol = ConcreteRSSParser()
    
    // MARK: - Repositories (Data Layer)
    lazy var networkRepository: NetworkRepositoryProtocol = UnifiedNetworkService.shared
    
    lazy var subscriptionRepository: SubscriptionRepositoryProtocol = GRDBSubscriptionRepository(
        dbManager: databaseManager,
        cacheStore: memoryCacheStore,
        networkRepository: networkRepository
    )
    
    lazy var podcastRepository: PodcastRepositoryProtocol = GRDBPodcastRepository(
        dbManager: databaseManager,
        cacheStore: memoryCacheStore,
        networkRepository: networkRepository,
        rssParser: rssParser
    )
    
    lazy var episodeRepository: EpisodeRepositoryProtocol = GRDBEpisodeRepository(
        dbManager: databaseManager,
        cacheStore: memoryCacheStore,
        networkRepository: networkRepository,
        rssParser: rssParser
    )
    
    lazy var playbackStateRepository: PlaybackStateRepositoryProtocol = GRDBPlaybackStateRepository(
        dbManager: databaseManager
    )
    
    lazy var showRepository: ShowRepositoryProtocol = GRDBShowRepository(
        dbManager: databaseManager,
        cacheStore: memoryCacheStore
    )

    private init() {}
} 