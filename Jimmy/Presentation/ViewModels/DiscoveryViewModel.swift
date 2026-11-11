import Foundation
import Combine
import os
import JimmyKit

struct DiscoverState: Equatable {
    var isLoadingLanding = false
    var isSearching = false
    var errorMessage: String?
}

/// A trending episode slot on the Discover screen — really a top-chart podcast shown with a
/// generic "Latest Episode" placeholder, since Apple's charts feed doesn't carry per-episode
/// data. Previously defined on the now-deleted `DiscoveryService`.
struct TrendingEpisode: Identifiable, Codable {
    let id: Int
    let title: String
    let podcastName: String
    let feedURL: URL
    let artworkURL: URL?
}

/// Thrown by `DiscoveryViewModel.withTimeout(seconds:operation:)` when `operation` doesn't finish
/// in time. Previously defined on the now-deleted `BackgroundRefreshService` (an unrelated type
/// that happened to also declare one); this is its only remaining caller.
private struct TimeoutError: Error {}

/// ViewModel for Discovery functionality following MVVM patterns
@MainActor
class DiscoveryViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "DiscoveryViewModel")
    static let shared = DiscoveryViewModel(directory: PodcastDirectory())
    // MARK: - Published Properties
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var hasAnyData: Bool = false
    @Published var showingSubscriptionAlert: Bool = false
    @Published var subscriptionMessage: String = ""
    @Published var subscriptionError: SubscriptionError?
    @Published var isSearching: Bool = false
    @Published var searchResults: [PodcastSearchResult] = []
    @Published var featured: [PodcastSearchResult] = []
    @Published var trending: [TrendingEpisode] = []
    @Published var charts: [PodcastSearchResult] = []
    @Published var errorMessage: String?
    @Published private(set) var state = DiscoverState()

    // MARK: - Private Properties
    /// Apple Podcasts search and charts (JimmyKit). Injectable so tests can stub it instead of
    /// hitting the network.
    private let directory: PodcastDirectory
    /// Feed URLs with a subscribe in flight, for `isProcessing(_:)`.
    private var processingFeedURLs: Set<URL> = []
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    // MARK: - Initialization
    init(directory: PodcastDirectory) {
        self.directory = directory
        setupSearchBinding()
    }

    deinit {
        cancellables.removeAll()
        searchTask?.cancel()
    }

    // MARK: - Private Methods
    private func setupSearchBinding() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
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
        state.isLoadingLanding = true
        state.errorMessage = nil

        do {
            // Add timeout protection to prevent hanging
            let (entries, lookedUp): ([PodcastDirectoryChartEntry], [PodcastDirectoryResult]) = try await withTimeout(seconds: 15) {
                let entries = try await self.directory.topChartEntries(limit: 50)
                let lookedUp = try await self.directory.lookup(ids: entries.map(\.id))
                return (entries, lookedUp)
            }

            let chartResults = lookedUp.map(Self.podcastSearchResult(from:))
            featured = Array(chartResults.prefix(20))
            charts = chartResults
            // Positions 21-30: a different slice from the same chart fetch, so "trending"
            // doesn't just repeat "featured".
            let trendingStart = 20
            let trendingEnd = min(trendingStart + 10, entries.count)
            trending = trendingStart < trendingEnd
                ? entries[trendingStart..<trendingEnd].map(Self.trendingEpisode(from:))
                : []
            hasAnyData = !featured.isEmpty || !trending.isEmpty || !charts.isEmpty
            errorMessage = nil
            state.errorMessage = nil

        } catch {
            errorMessage = "Failed to load discovery content: \(error.localizedDescription)"
            state.errorMessage = errorMessage
            Self.logger.error("DiscoveryViewModel: Failed to refresh data - \(error.localizedDescription)")

            // Keep existing data if available
            hasAnyData = !featured.isEmpty || !trending.isEmpty || !charts.isEmpty
        }

        isLoading = false
        state.isLoadingLanding = false
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
            state.isSearching = false
            errorMessage = nil
            state.errorMessage = nil
            return
        }

        let latencyToken = InteractionLatencyTracker.shared.begin(.discoverSearch, detail: query)
        isSearching = true
        state.isSearching = true
        errorMessage = nil
        state.errorMessage = nil

        let results = (try? await directory.search(query: query))?.map(Self.podcastSearchResult(from:)) ?? []

        // Check if this search is still current
        guard query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else {
            InteractionLatencyTracker.shared.end(latencyToken)
            return
        }

        searchResults = results
        isSearching = false
        state.isSearching = false
        Task {
            await DiscoverSearchTip.searchedCatalog.donate()
        }
        InteractionLatencyTracker.shared.end(latencyToken)
    }

    func isSubscribed(_ result: PodcastSearchResult) -> Bool {
        AppModel.current?.podcasts.contains { $0.feedURL == result.feedURL } ?? false
    }

    func isProcessing(_ result: PodcastSearchResult) -> Bool {
        processingFeedURLs.contains(result.feedURL)
    }

    func subscribe(to result: PodcastSearchResult) async {
        processingFeedURLs.insert(result.feedURL)
        defer { processingFeedURLs.remove(result.feedURL) }
        do {
            guard let podcast = try await AppModel.current?.subscribe(feedURL: result.feedURL) else {
                throw AppModelError.storeNotReady
            }

            subscriptionMessage = "Successfully subscribed to \(podcast.title)"
            subscriptionError = nil
            showingSubscriptionAlert = true

            Self.logger.info("DiscoveryViewModel: Successfully subscribed to \(result.title)")

        } catch {
            // Handle unexpected errors
            subscriptionError = .unknownError(error.localizedDescription)
            subscriptionMessage = "Failed to subscribe to \(result.title): \(error.localizedDescription)"
            showingSubscriptionAlert = true

            Self.logger.error("DiscoveryViewModel: Unexpected error subscribing to \(result.title): \(error)")
        }
    }

    func clearSearch() {
        searchText = ""
        searchResults = []
        isSearching = false
        state.isSearching = false
    }

    func dismissSubscriptionAlert() {
        showingSubscriptionAlert = false
        subscriptionMessage = ""
    }

    // MARK: - Utility Functions

    /// Converts a `JimmyKit.PodcastDirectoryResult` into the app's own `PodcastSearchResult`,
    /// so screens and views keep the type they already render.
    private static func podcastSearchResult(from result: PodcastDirectoryResult) -> PodcastSearchResult {
        PodcastSearchResult(
            id: result.id,
            title: result.title,
            author: result.author,
            feedURL: result.feedURL,
            artworkURL: result.artworkURL,
            description: result.description,
            genre: result.genre,
            trackCount: result.trackCount
        )
    }

    /// Builds a placeholder "trending episode" from a raw chart entry (no per-episode data is
    /// available from Apple's charts feed) — same synthesized title and feed link the old
    /// `DiscoveryService.fetchTrendingEpisodes` used.
    private static func trendingEpisode(from entry: PodcastDirectoryChartEntry) -> TrendingEpisode {
        let feedURL = URL(string: "https://podcasts.apple.com/podcast/id\(entry.id)")
            ?? URL(string: "https://example.com")!
        return TrendingEpisode(
            id: entry.id,
            title: "Latest Episode",
            podcastName: entry.name,
            feedURL: feedURL,
            artworkURL: entry.artworkURL
        )
    }

    /// Add timeout to async operations to prevent hanging
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }

            guard let result = try await group.next() else {
                throw TimeoutError()
            }

            group.cancelAll()
            return result
        }
    }
}
