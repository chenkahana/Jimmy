import Foundation
import Combine
import os

/// Phase 6: Enhanced with error handling and task management
@MainActor
class PodcastSearchViewModel: ObservableObject, TaskManagedViewModel {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "PodcastSearchViewModel")
    @Published var searchText: String = ""
    @Published var searchScope: SearchScope = .all
    @Published var searchResults: [PodcastSearchResult] = []
    @Published var isSearching: Bool = false
    @Published var showingSubscriptionAlert: Bool = false
    @Published var subscriptionMessage: String = ""
    @Published var subscriptionError: SubscriptionError?
    @Published var errorMessage: String = ""
    
    // MARK: - Task Management (Phase 6)
    let taskManager = TaskCancellationManager()
    let errorManager = ErrorStateManager()
    private let retryManager = RetryManager.shared

    enum SearchScope: String, CaseIterable {
        case all = "All"
        case subscribed = "Subscribed"
        case web = "Discover"
        
        var icon: String {
            switch self {
            case .all: return "magnifyingglass"
            case .subscribed: return "person.crop.circle"
            case .web: return "globe"
            }
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private let searchService: ITunesSearchServiceProtocol
    /// Feed URLs with a subscribe in flight, for `isProcessing(_:)`.
    @Published private var processingFeedURLs: Set<URL> = []

    init(searchService: ITunesSearchServiceProtocol = iTunesSearchService.shared) {
        self.searchService = searchService
        setupSearchDebounce()
    }

    // MARK: - TaskManagedViewModel Protocol
    
    func onViewAppear() {
        // Subscription states are managed by SubscriptionStateManager
        // No need to manually load local podcasts
    }
    
    func onViewDisappear() {
        // Automatically handled by TaskManagedViewModel extension
        taskManager.cancelAllTasks()
    }

    private func setupSearchDebounce() {
        $searchText
            .removeDuplicates()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] text in
                self?.performSearch()
            }
            .store(in: &cancellables)
    }

    func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        if searchScope == .subscribed {
            // Local search only
            return
        }
        
        let trimmedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if the search text is a URL
        if trimmedText.hasPrefix("http://") || trimmedText.hasPrefix("https://") {
            // Handle as direct URL import
            handleDirectURLImport(trimmedText)
            return
        }
        
        // Cancel any existing search
        taskManager.cancelGroup("search")
        
        isSearching = true
        errorManager.clearError()
        
        let searchTask = Task.managed(
            id: "podcast-search",
            group: "search",
            manager: taskManager
        ) {
            do {
                let results = await self.searchService.searchPodcasts(query: self.searchText)
                
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
                
            } catch {
                // Handle 304 Not Modified as success case (though unlikely for search)
                if let fetchError = error as? FetchError, case .notModified = fetchError {
                    await MainActor.run {
                        // 304 Not Modified means cached results are still valid
                        self.isSearching = false
                    }
                    return
                }
                
                // For other errors, try with retry logic
                do {
                    let results = try await self.retryManager.executeWithRetry(
                        operation: {
                            await self.searchService.searchPodcasts(query: self.searchText)
                        },
                        shouldRetry: RetryManager.shouldRetryNetworkError
                    )
                    
                    await MainActor.run {
                        self.searchResults = results
                        self.isSearching = false
                    }
                    
                } catch {
                    await MainActor.run {
                        self.isSearching = false
                        let friendlyMessage = self.getFriendlyErrorMessage(error)
                        self.errorManager.showError(friendlyMessage) { [weak self] in
                            self?.performSearch()
                        }
                    }
                }
            }
        }
    }
    
    /// Handle direct URL import when user enters a URL in search field
    private func handleDirectURLImport(_ urlString: String) {
        Self.logger.info("Search URL Import: Attempting to import URL: \(urlString)")
        
        // Cancel any existing search
        taskManager.cancelGroup("search")
        
        isSearching = true
        errorManager.clearError()
        
        let importTask = Task.managed(
            id: "url-import",
            group: "search",
            manager: taskManager
        ) {
            do {
                Self.logger.info("Search URL Import: Starting import from URL: \(urlString)")
                // Try to add the podcast directly from the URL
                guard let podcast = try await AppModel.current?.subscribe(feedURL: URL(string: urlString)!) else {
                    throw AppModelError.storeNotReady
                }
                Self.logger.info("Search URL Import: Successfully imported \(podcast.title)")

                await MainActor.run {
                    self.isSearching = false
                    self.subscriptionMessage = "Successfully subscribed to \(podcast.title)"
                    self.subscriptionError = nil
                    self.showingSubscriptionAlert = true
                    self.searchText = "" // Clear search after successful import
                }
                
            } catch {
                Self.logger.error("Search URL Import: Failed to import podcast: \(error.localizedDescription)")
                await MainActor.run {
                    self.isSearching = false
                    let friendlyMessage = self.getFriendlyErrorMessage(error)
                    self.errorManager.showError("Failed to import podcast from URL: \(friendlyMessage)") { [weak self] in
                        self?.handleDirectURLImport(urlString)
                    }
                }
            }
        }
    }

    func isSubscribed(_ result: PodcastSearchResult) -> Bool {
        AppModel.current?.podcasts.contains { $0.feedURL == result.feedURL } ?? false
    }

    func isProcessing(_ result: PodcastSearchResult) -> Bool {
        processingFeedURLs.contains(result.feedURL)
    }
    
    func getSubscribedPodcasts() async -> [Podcast] {
        do {
            return try await DIContainer.shared.subscriptionRepository.fetchSubscriptions(ignoreCache: false)
        } catch {
            Self.logger.error("PodcastSearchViewModel: Failed to fetch subscribed podcasts: \(error)")
            return []
        }
    }

    func subscribe(to result: PodcastSearchResult) async {
        processingFeedURLs.insert(result.feedURL)
        let subscribeTask = Task.managed(
            id: "subscribe-\(result.feedURL.absoluteString)",
            manager: taskManager
        ) { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.processingFeedURLs.remove(result.feedURL)
                }
            }
            do {
                guard let podcast = try await AppModel.current?.subscribe(feedURL: result.feedURL) else {
                    throw AppModelError.storeNotReady
                }

                await MainActor.run {
                    self?.subscriptionMessage = "Successfully subscribed to \(podcast.title)"
                    self?.subscriptionError = nil
                    self?.showingSubscriptionAlert = true
                }

                Self.logger.info("PodcastSearchViewModel: Successfully subscribed to \(result.title)")

            } catch {
                // Handle unexpected errors
                await MainActor.run {
                    self?.subscriptionError = .unknownError(error.localizedDescription)
                    self?.subscriptionMessage = "Failed to subscribe to \(result.title): \(error.localizedDescription)"
                    self?.showingSubscriptionAlert = true
                }

                Self.logger.error("PodcastSearchViewModel: Unexpected error subscribing to \(result.title): \(error)")
            }
        }
    }
    
    /// Get user-friendly error message
    private func getFriendlyErrorMessage(_ error: Error) -> String {
        if error is CancellationError {
            return "Operation was cancelled"
        }
        
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return "No internet connection. Please check your network and try again."
        case NSURLErrorTimedOut:
            return "Request timed out. Please try again."
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return "Cannot connect to server. Please try again later."
        case NSURLErrorNetworkConnectionLost:
            return "Network connection lost. Please check your connection and retry."
        default:
            return error.localizedDescription
        }
    }

    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
} 