import Foundation
import Combine
import os
import JimmyKit

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
    /// Starts true: Discover loads the chart as soon as it appears, so its first frame shows placeholders, not
    /// the error.
    @Published var isLoading: Bool = true
    @Published var isSearching: Bool = false
    @Published var searchResults: [PodcastSearchResult] = []
    /// The trimmed query whose results `searchResults` holds, set once a search finishes. "No Results" is
    /// only true for this query, never for text that hasn't been searched yet.
    @Published private(set) var lastCompletedQuery: String?
    /// Why the last search failed, if it did. Kept apart from `errorMessage`, which is about the charts.
    @Published private(set) var searchErrorMessage: String?
    /// Apple's top podcasts chart, in rank order.
    @Published var charts: [PodcastSearchResult] = []
    /// Why the charts failed to load, if they did.
    @Published var errorMessage: String?
    /// Why the last subscribe failed; non-nil presents the failure alert.
    @Published var subscribeFailure: String?
    /// Feed URLs with a subscribe in flight, for `isProcessing(_:)`.
    @Published private(set) var processingFeedURLs: Set<URL> = []

    var hasAnyData: Bool { !charts.isEmpty }

    // MARK: - Private Properties
    /// Apple Podcasts search and charts (JimmyKit). Injectable so tests can stub it instead of
    /// hitting the network.
    private let directory: PodcastDirectory
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    // MARK: - Initialization
    init(directory: PodcastDirectory) {
        self.directory = directory
        setupSearchBinding()
    }

    deinit {
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

        do {
            // Add timeout protection to prevent hanging
            let (entries, lookedUp): ([PodcastDirectoryChartEntry], [PodcastDirectoryResult]) = try await withTimeout(seconds: 15) {
                let entries = try await self.directory.topChartEntries(limit: 50)
                let lookedUp = try await self.directory.lookup(ids: entries.map(\.id))
                return (entries, lookedUp)
            }

            // The lookup doesn't promise the chart's order; put the shows back in rank order.
            let resultsByID = Dictionary(lookedUp.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            charts = entries.compactMap { resultsByID[$0.id] }.map(Self.podcastSearchResult(from:))
        } catch {
            errorMessage = error.localizedDescription
            Self.logger.error("DiscoveryViewModel: Failed to refresh data - \(error.localizedDescription)")
        }

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
            searchErrorMessage = nil
            lastCompletedQuery = query
            return
        }

        let latencyToken = InteractionLatencyTracker.shared.begin(.discoverSearch, detail: query)
        isSearching = true

        let outcome: Result<[PodcastSearchResult], Error>
        do {
            outcome = .success(try await directory.search(query: query).map(Self.podcastSearchResult(from:)))
        } catch {
            outcome = .failure(error)
        }

        // A newer query has taken over; its own search sets the state.
        guard !Task.isCancelled, query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else {
            InteractionLatencyTracker.shared.end(latencyToken)
            return
        }

        switch outcome {
        case .success(let results):
            searchResults = results
            searchErrorMessage = nil
        case .failure(let error):
            searchResults = []
            searchErrorMessage = error.localizedDescription
            Self.logger.error("DiscoveryViewModel: Search failed - \(error.localizedDescription)")
        }
        lastCompletedQuery = query
        isSearching = false
        Task {
            await DiscoverSearchTip.searchedCatalog.donate()
        }
        InteractionLatencyTracker.shared.end(latencyToken)
    }

    /// Feed URLs of every subscribed show, for checking many rows against one set.
    func subscribedFeedURLs() -> Set<URL> {
        Set(AppModel.current?.podcasts.map(\.feedURL) ?? [])
    }

    func isProcessing(_ result: PodcastSearchResult) -> Bool {
        processingFeedURLs.contains(result.feedURL)
    }

    func subscribe(to result: PodcastSearchResult) async {
        guard !processingFeedURLs.contains(result.feedURL) else { return }
        processingFeedURLs.insert(result.feedURL)
        defer { processingFeedURLs.remove(result.feedURL) }
        do {
            guard try await AppModel.current?.subscribe(feedURL: result.feedURL) != nil else {
                throw AppModelError.storeNotReady
            }
            Self.logger.info("DiscoveryViewModel: Successfully subscribed to \(result.title)")
        } catch {
            subscribeFailure = error.localizedDescription
            Self.logger.error("DiscoveryViewModel: Unexpected error subscribing to \(result.title): \(error)")
        }
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

    /// Add timeout to async operations to prevent hanging
    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
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
