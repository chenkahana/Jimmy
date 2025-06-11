import Foundation

// MARK: - Dependency Injection Container
// Wires together all layers of the clean architecture

final class DIContainer {
    static let shared = DIContainer()
    
    // MARK: - Stores (Actors for thread safety)
    lazy var podcastStore: CleanPodcastStoreProtocol = CleanPodcastStore.shared
    lazy var episodeStore: CleanEpisodeStoreProtocol = CleanEpisodeStore.shared
    lazy var queueStore = QueueStore.shared
    
    // MARK: - Repositories (Data Layer)
    lazy var networkRepository: NetworkRepositoryProtocol = ConcreteNetworkRepository(
        networkMonitor: networkMonitor
    )
    
    lazy var storageRepository: StorageRepositoryProtocol = ConcreteStorageRepository()
    
    lazy var podcastRepository: PodcastRepositoryProtocol = ConcretePodcastRepository(
        networkRepository: networkRepository,
        storageRepository: storageRepository,
        rssParser: rssParser
    )
    
    lazy var episodeRepository: EpisodeRepositoryProtocol = ConcreteEpisodeRepository(
        networkRepository: networkRepository,
        storageRepository: storageRepository,
        rssParser: rssParser
    )
    
    lazy var searchRepository: SearchRepositoryProtocol = ConcreteiTunesSearchRepository()
    
    // MARK: - Supporting Services
    lazy var rssParser: RSSParserProtocol = ConcreteRSSParser()
    lazy var networkMonitor: NetworkMonitorProtocol = ConcreteNetworkMonitor()
    
    // MARK: - Use Cases (Business Logic)
    lazy var fetchPodcastsUseCase = FetchPodcastsUseCase(
        repository: podcastRepository,
        store: podcastStore
    )
    
    lazy var subscribeToPodcastUseCase = SubscribeToPodcastUseCase(
        repository: podcastRepository,
        store: podcastStore,
        episodeStore: episodeStore
    )
    
    lazy var unsubscribeFromPodcastUseCase = UnsubscribeFromPodcastUseCase(
        repository: podcastRepository,
        store: podcastStore,
        episodeStore: episodeStore
    )
    
    lazy var refreshEpisodesUseCase = RefreshEpisodesUseCase(
        repository: episodeRepository,
        store: episodeStore
    )
    
    lazy var searchPodcastsUseCase = SearchPodcastsUseCase(
        searchRepository: searchRepository
    )
    
    // MARK: - ViewModels (Presentation Layer)
    @MainActor
    lazy var libraryViewModel = CleanLibraryViewModel(
        fetchPodcastsUseCase: fetchPodcastsUseCase,
        subscribeToPodcastUseCase: subscribeToPodcastUseCase,
        unsubscribeFromPodcastUseCase: unsubscribeFromPodcastUseCase,
        refreshEpisodesUseCase: refreshEpisodesUseCase,
        podcastStore: podcastStore,
        episodeStore: episodeStore
    )
    
    @MainActor
    lazy var queueViewModel = CleanQueueViewModel(
        queueStore: queueStore
    )
    
    @MainActor
    lazy var discoveryViewModel = CleanDiscoveryViewModel(
        searchPodcastsUseCase: searchPodcastsUseCase,
        subscribeToPodcastUseCase: subscribeToPodcastUseCase
    )
    
    private init() {}
} 