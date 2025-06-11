import Foundation
import SwiftUI

/// Unified controller for discovery functionality
@MainActor
class UnifiedDiscoveryController: ObservableObject {
    static let shared = UnifiedDiscoveryController()
    
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
    
    private let discoveryService = DiscoveryService.shared
    private let searchService = iTunesSearchService.shared
    private let podcastService = PodcastService.shared
    
    private init() {
        // Start with empty data, load on demand
    }
    
    func refreshData() async {
        print("🔄 UnifiedDiscoveryController: Refreshing data")
        isLoading = true
        
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
        print("📚 UnifiedDiscoveryController: Loading data if needed")
        
        // Only load if we don't have any data
        guard !hasAnyData else { return }
        
        await refreshData()
    }
    
    func searchPodcasts() async {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        let results = await withCheckedContinuation { continuation in
            searchService.searchPodcasts(query: searchText) { results in
                continuation.resume(returning: results)
            }
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
} 