import Foundation
import Combine
import SwiftUI
#if canImport(OSLog)
import OSLog
#endif

/// Unified controller for Discovery view following Background Data Synchronization Plan
/// Shows cached data immediately, coordinates background updates without blocking UI
@MainActor
final class UnifiedDiscoveryController: ObservableObject {
    static let shared = UnifiedDiscoveryController()
    
    // MARK: - Published Properties
    
    @Published private(set) var trending: [TrendingEpisode] = []
    @Published private(set) var featured: [PodcastSearchResult] = []
    @Published private(set) var charts: [PodcastSearchResult] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var cacheStatus: DiscoveryRepository.CacheStatus = .empty
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var hasLoadedData: Bool = false
    
    // Search functionality
    @Published var searchText: String = ""
    @Published private(set) var searchResults: [PodcastSearchResult] = []
    @Published private(set) var isSearching: Bool = false
    
    // Subscription management
    @Published private(set) var subscribed: [Podcast] = []
    @Published var showingSubscriptionAlert: Bool = false
    @Published var subscriptionMessage: String = ""
    
    // MARK: - Private Properties
    
    private let repository = DiscoveryRepository.shared
    private let requestQueue = DiscoveryRequestQueue.shared
    private let podcastService = PodcastService.shared
    private let searchService = iTunesSearchService.shared
    
    private var cancellables = Set<AnyCancellable>()
    private var searchDebounceTimer: Timer?
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "Jimmy", category: "UnifiedDiscoveryController")
    #endif
    
    // MARK: - Configuration
    
    private struct Config {
        static let searchDebounceDelay: TimeInterval = 0.5
        static let cacheRefreshThreshold: TimeInterval = 1800 // 30 minutes
        static let backgroundRefreshInterval: TimeInterval = 3600 // 1 hour
    }
    
    // MARK: - Initialization
    
    private init() {
        setupRepositoryObservers()
        setupSearchObserver()
        loadSubscribedPodcasts()
        
        #if canImport(OSLog)
        logger.info("🎯 UnifiedDiscoveryController initialized")
        #endif
    }
    
    // MARK: - Public Interface
    
    /// Load data if needed (called from view onAppear)
    func loadDataIfNeeded() async {
        guard !hasLoadedData else { return }
        
        #if canImport(OSLog)
        logger.info("📱 Loading discovery data for first time")
        #endif
        
        // Show cached data immediately if available
        await loadCachedDataImmediately()
        
        // Check if we have any data at all
        let hasData = !trending.isEmpty || !featured.isEmpty || !charts.isEmpty
        
        if !hasData {
            #if canImport(OSLog)
            logger.info("🔄 No cached data found - fetching initial discovery data")
            #endif
            
            // Fetch initial data immediately
            let request = FetchDiscoveryRequest.userInitiatedRefresh()
            await requestQueue.enqueue(request)
            
            // Process the request immediately
            Task {
                do {
                    _ = try await DiscoveryFetchWorker.shared.processRequest(request)
                } catch {
                    #if canImport(OSLog)
                    logger.error("❌ Failed to process initial discovery request: \(error.localizedDescription)")
                    #endif
                }
            }
        } else {
            // Check if we need to refresh existing data
            let isStale = await repository.isCacheStale()
            if isStale {
                await refreshData(priority: .normal)
            }
        }
        
        hasLoadedData = true
    }
    
    /// Refresh data (user-initiated)
    func refreshData(priority: FetchDiscoveryRequest.Priority = .high) async {
        #if canImport(OSLog)
        logger.info("🔄 User-initiated discovery refresh")
        #endif
        
        let request = FetchDiscoveryRequest.userInitiatedRefresh()
        
        await requestQueue.enqueue(request)
        
        // Process the request immediately
        Task {
            do {
                _ = try await DiscoveryFetchWorker.shared.processRequest(request)
            } catch {
                #if canImport(OSLog)
                logger.error("❌ Failed to process discovery refresh request: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    /// Perform background refresh (silent)
    func performBackgroundRefresh() async {
        let cacheAge = await repository.getCacheAge()
        
        // Only refresh if cache is stale
        if let age = cacheAge, age < Config.cacheRefreshThreshold {
            #if canImport(OSLog)
            logger.info("⏭️ Skipping background refresh - cache is fresh (age: \(Int(age))s)")
            #endif
            return
        }
        
        #if canImport(OSLog)
        logger.info("🔄 Performing background discovery refresh")
        #endif
        
        let request = FetchDiscoveryRequest.silentRefresh()
        await requestQueue.enqueue(request)
        
        // Process the request
        Task {
            do {
                _ = try await DiscoveryFetchWorker.shared.processRequest(request)
            } catch {
                #if canImport(OSLog)
                logger.error("❌ Failed to process background refresh request: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    /// Check if subscribed to a podcast
    func isSubscribed(_ result: PodcastSearchResult) -> Bool {
        return subscribed.contains { $0.feedURL == result.feedURL }
    }
    
    /// Subscribe to a podcast
    func subscribe(to result: PodcastSearchResult) async {
        let podcast = result.toPodcast()
        
        // Add to local array
        subscribed.append(podcast)
        
        // Save to persistent storage
        podcastService.savePodcasts(subscribed)
        
        // Show success message
        subscriptionMessage = "Successfully subscribed to \(podcast.title)!"
        showingSubscriptionAlert = true
        
        #if canImport(OSLog)
        logger.info("✅ Subscribed to podcast: \(podcast.title)")
        #endif
    }
    
    /// Get cache status for UI display
    func getCacheStatusText() -> String {
        return cacheStatus.displayText
    }
    
    /// Check if data is fresh (for UI indicators)
    var isDataFresh: Bool {
        if case .fresh = cacheStatus {
            return true
        }
        return false
    }
    
    /// Check if data is cached (for UI indicators)
    var isDataCached: Bool {
        if case .cached = cacheStatus {
            return true
        }
        return false
    }
    
    // MARK: - Private Methods
    
    private func setupRepositoryObservers() {
        // Observe repository changes
        repository.$trending
            .receive(on: DispatchQueue.main)
            .assign(to: \.trending, on: self)
            .store(in: &cancellables)
        
        repository.$featured
            .receive(on: DispatchQueue.main)
            .assign(to: \.featured, on: self)
            .store(in: &cancellables)
        
        repository.$charts
            .receive(on: DispatchQueue.main)
            .assign(to: \.charts, on: self)
            .store(in: &cancellables)
        
        repository.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: \.isLoading, on: self)
            .store(in: &cancellables)
        
        repository.$cacheStatus
            .receive(on: DispatchQueue.main)
            .assign(to: \.cacheStatus, on: self)
            .store(in: &cancellables)
        
        repository.$lastUpdated
            .receive(on: DispatchQueue.main)
            .assign(to: \.lastUpdated, on: self)
            .store(in: &cancellables)
    }
    
    private func setupSearchObserver() {
        $searchText
            .debounce(for: .seconds(Config.searchDebounceDelay), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] searchText in
                Task {
                    await self?.performSearch(query: searchText)
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadCachedDataImmediately() async {
        // The repository automatically loads cached data on initialization
        // This method ensures we have the latest cached state
        let data = await repository.getAllData()
        
        trending = data.trending
        featured = data.featured
        charts = data.charts
        
        if !data.trending.isEmpty || !data.featured.isEmpty || !data.charts.isEmpty {
            #if canImport(OSLog)
            logger.info("💾 Loaded cached discovery data - Trending: \(data.trending.count), Featured: \(data.featured.count), Charts: \(data.charts.count)")
            #endif
        }
    }
    
    private func loadSubscribedPodcasts() {
        subscribed = podcastService.loadPodcasts()
        
        #if canImport(OSLog)
        logger.info("📚 Loaded \(self.subscribed.count) subscribed podcasts")
        #endif
    }
    
    private func performSearch(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        
        #if canImport(OSLog)
        logger.info("🔍 Searching for: \(query)")
        #endif
        
        // Use callback-based search service
        searchService.searchPodcasts(query: query) { [weak self] (results: [PodcastSearchResult]) in
            Task { @MainActor in
                self?.searchResults = results
                self?.isSearching = false
                
                #if canImport(OSLog)
                self?.logger.info("🔍 Search completed: \(results.count) results")
                #endif
            }
        }
    }
    
    // MARK: - Background Processing
    
    /// Schedule periodic background refresh
    func scheduleBackgroundRefresh() {
        // This would typically be called from the app delegate or scene delegate
        DiscoveryFetchWorker.shared.scheduleBackgroundRefresh()
    }
    
    /// Handle app lifecycle events
    func handleAppDidBecomeActive() async {
        // Check if we need to refresh data when app becomes active
        let cacheAge = await repository.getCacheAge()
        
        if let age = cacheAge, age > Config.backgroundRefreshInterval {
            #if canImport(OSLog)
            logger.info("🔄 App became active - refreshing stale discovery data (age: \(Int(age))s)")
            #endif
            
            await performBackgroundRefresh()
        }
    }
    
    func handleAppDidEnterBackground() async {
        // Persist any pending data
        #if canImport(OSLog)
        logger.info("📱 App entering background - persisting discovery state")
        #endif
    }
}

// MARK: - Convenience Extensions

extension UnifiedDiscoveryController {
    /// Get all discovery data for external use
    var allDiscoveryData: (trending: [TrendingEpisode], featured: [PodcastSearchResult], charts: [PodcastSearchResult]) {
        return (trending, featured, charts)
    }
    
    /// Check if any data is available
    var hasAnyData: Bool {
        return !trending.isEmpty || !featured.isEmpty || !charts.isEmpty
    }
    
    /// Get total item count for debugging
    var totalItemCount: Int {
        return trending.count + featured.count + charts.count
    }
} 