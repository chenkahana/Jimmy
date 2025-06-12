import Foundation
import Combine

/// ViewModel for Discovery functionality following MVVM patterns
@MainActor
class DiscoveryViewModel: ObservableObject {
    static let shared = DiscoveryViewModel()
    // MARK: - Published Properties
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var hasAnyData: Bool = false
    @Published var showingSubscriptionAlert: Bool = false
    @Published var subscriptionMessage: String = ""
    @Published var isSearching: Bool = false
    @Published var searchResults: [PodcastSearchResult] = []
    @Published var featured: [PodcastSearchResult] = []
    @Published var trending: [TrendingEpisode] = []
    @Published var charts: [PodcastSearchResult] = []
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private let discoveryService: DiscoveryService
    private let searchService: iTunesSearchService
    private let podcastService: PodcastService
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    
    // MARK: - Initialization
    private init(
        discoveryService: DiscoveryService = .shared,
        searchService: iTunesSearchService = .shared,
        podcastService: PodcastService = .shared
    ) {
        self.discoveryService = discoveryService
        self.searchService = searchService
        self.podcastService = podcastService
        setupSearchBinding()
    }
    
    deinit {
        cancellables.removeAll()
        searchTask?.cancel()
    }
    
    // MARK: - Private Methods
    private func setupSearchBinding() {
        $searchText
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] searchText in
                self?.searchTask?.cancel()
                self?.searchTask = Task { [weak self] in
                    await self?.searchPodcasts()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    func refreshData() async {
        isLoading = true
        errorMessage = nil
        
        async let featuredTask = discoveryService.fetchFeaturedPodcasts(limit: 20)
        async let trendingTask = discoveryService.fetchTrendingEpisodes(limit: 10)
        async let chartsTask = discoveryService.fetchTopCharts(limit: 50)
        
        let (featuredResults, trendingResults, chartsResults) = await (featuredTask, trendingTask, chartsTask)
        
        featured = featuredResults
        trending = trendingResults
        charts = chartsResults
        hasAnyData = !featured.isEmpty || !trending.isEmpty || !charts.isEmpty
        
        isLoading = false
    }
    
    func loadDataIfNeeded() async {
        // Only load if we don't have any data
        guard !hasAnyData else { return }
        await refreshData()
    }
    
    func searchPodcasts() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        errorMessage = nil
        
        let results = await withCheckedContinuation { continuation in
            searchService.searchPodcasts(query: query) { results in
                continuation.resume(returning: results)
            }
        }
        
        // Check if this search is still current
        guard query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }
        
        searchResults = results
        
        isSearching = false
    }
    
    func isSubscribed(_ result: PodcastSearchResult) -> Bool {
        let localPodcasts = podcastService.loadPodcasts()
        return localPodcasts.contains { $0.feedURL == result.feedURL }
    }
    
    func subscribe(to result: PodcastSearchResult) async {
        // Check if already subscribed
        if isSubscribed(result) {
            subscriptionMessage = "You're already subscribed to \(result.title)"
            showingSubscriptionAlert = true
            return
        }
        
        // Add to subscriptions
        let podcast = result.toPodcast()
        var podcasts = podcastService.loadPodcasts()
        podcasts.append(podcast)
        podcastService.savePodcasts(podcasts)
        
        subscriptionMessage = "Successfully subscribed to \(result.title)"
        showingSubscriptionAlert = true
    }
    
    func clearSearch() {
        searchText = ""
        searchResults = []
    }
    
    func dismissSubscriptionAlert() {
        showingSubscriptionAlert = false
        subscriptionMessage = ""
    }
} 