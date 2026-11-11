import Foundation

// MARK: - Dependency Injection Container
// Wires together all layers of the clean architecture

final class DIContainer {
    static let shared = DIContainer()
    
    // MARK: - Stores (Actors for thread safety)
    lazy var podcastStore: CleanPodcastStoreProtocol = CleanPodcastStore.shared
    lazy var episodeStore: CleanEpisodeStoreProtocol = CleanEpisodeStore.shared
    lazy var queueStore = QueueStore.shared
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
    
    lazy var searchRepository: SearchRepositoryProtocol = ConcreteiTunesSearchRepository()
    
    lazy var showRepository: ShowRepositoryProtocol = GRDBShowRepository(
        dbManager: databaseManager,
        cacheStore: memoryCacheStore
    )
    
    // MARK: - Download Manager
    lazy var downloadManager = DownloadManager.shared

    // MARK: - Services
    // Fix circular dependency by creating PodcastService with explicit dependencies
    lazy var podcastService: PodcastServiceProtocol = {
        let service = PodcastService(
            podcastRepository: podcastRepository,
            episodeRepository: episodeRepository
        )
        // Initialize the shared instance for backward compatibility
        PodcastService.shared = service
        return service
    }()
    
    // MARK: - ViewModels
    @MainActor lazy var libraryViewModel = LibraryViewModel.shared
    
    private init() {}
} 