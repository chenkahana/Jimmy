import Foundation
import SwiftUI
import Combine

/// ViewState enum for proper state management as required by newFlowVerification.md
enum EpisodeViewState {
    case loading
    case loaded
    case error(String)
}

/// Phase 2: Streaming RSS & Incremental UI
/// Phase 5: Selective Reload & Delta Checks
/// ViewModel for displaying episodes with streaming support using new EpisodeService
/// Features: cancellable Task on MainActor, throttled diffable snapshots every 5 items or 0.2s
/// Supports conditional GET with ETag/If-Modified-Since for selective updates
@MainActor
final class ShowEpisodesViewModel: ObservableObject, TaskManagedViewModel {
    
    // MARK: - Published UI State
    @Published var displayedEpisodes: [EpisodeWithPlaybackState] = []
    @Published var state: EpisodeViewState = .loaded
    @Published var searchText: String = ""
    @Published var sortOrder: EpisodeSortOrder = .newestFirst
    @Published var filterType: EpisodeFilter = .all
    @Published var isStreaming: Bool = false
    @Published var streamProgress: String = ""
    
    // MARK: - Phase 2: Streaming & Task Management
    private let episodeService = EpisodeService.shared
    private let episodeRepository: EpisodeRepositoryProtocol
    private let isLocalFeed: Bool
    private var streamingTask: Task<Void, Never>?
    let taskManager = TaskCancellationManager()
    let errorManager = ErrorStateManager()
    private let retryManager = RetryManager.shared
    
    // MARK: - Phase 4: Pagination Support
    private var paginationTask: Task<Void, Never>?
    private var currentCursor: String? = nil
    private let pageLimit: Int = 20
    private var isLoadingPage: Bool = false
    
    // MARK: - Phase 5: Conditional GET Support
    private var currentEtag: String? = nil
    private var currentLastModified: String? = nil
    private var lastUpdateTime: Date? = nil
    
    // MARK: - Phase 2: Throttled UI Updates
    private var pendingEpisodes: [EpisodeWithPlaybackState] = []
    private var updateTimer: Timer?
    private let updateThrottleInterval: TimeInterval = 0.2 // 200ms throttle
    private let batchSize: Int = 5 // Flush every 5 episodes
    private var episodeCount: Int = 0
    
    // MARK: - Public Properties
    var hasMorePages: Bool {
        return !allEpisodes.isEmpty && canLoadMore
    }

    // MARK: - Internal State (accessible from extensions)
    internal let podcastID: UUID
    internal let feedURL: URL
    internal var allEpisodes: [EpisodeWithPlaybackState] = []
    internal var canLoadMore = true
    internal var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(
        podcastID: UUID,
        feedURL: URL,
        episodeRepository: EpisodeRepositoryProtocol = DIContainer.shared.episodeRepository
    ) {
        self.podcastID = podcastID
        self.feedURL = feedURL
        self.episodeRepository = episodeRepository
        self.isLocalFeed = feedURL.absoluteString.hasPrefix("local://")

        setupBindings()
    }
    
    // MARK: - TaskManagedViewModel Protocol
    
    func onViewAppear() async {
        if allEpisodes.isEmpty {
            await loadFirstPage()
        } else {
            // Check for updates using conditional GET
            await refreshIfNeeded()
        }
    }
    
    func onViewDisappear() async {
        stopStreaming()
        stopPagination()
        taskManager.cancelAllTasks()
    }
    
    deinit {
        // Note: Cannot call stopStreaming() here as it requires MainActor access
        // Cleanup will happen automatically when the object is deallocated
        streamingTask?.cancel()
        paginationTask?.cancel()
        updateTimer?.invalidate()
        cancellables.removeAll()
    }
    
    // MARK: - Phase 5: Conditional GET Methods
    
    /// Refreshes episodes only if the feed has been modified
    func refreshIfNeeded() async {
        // Don't refresh too frequently (minimum 5 minutes between checks)
        if let lastUpdate = lastUpdateTime,
           Date().timeIntervalSince(lastUpdate) < 300 {
            return
        }
        if isLocalFeed {
            await loadLocalEpisodes()
            lastUpdateTime = Date()
            return
        }
        do {
            let (isModified, newEtag, newLastModified) = try await episodeService.checkFeedModified(
                feedURL: feedURL,
                etag: currentEtag,
                lastModified: currentLastModified
            )
            
            if isModified {
                await refreshEpisodes()
            } else {
                lastUpdateTime = Date()
            }
            
            // Update headers regardless
            currentEtag = newEtag
            currentLastModified = newLastModified
            
        } catch {
            // Fallback to regular refresh on error
            await refreshEpisodes()
        }
    }
    
    /// Refreshes episodes by clearing cache and reloading
    func refreshEpisodes() async {

        // Reset state
        currentCursor = nil
        allEpisodes.removeAll()
        displayedEpisodes.removeAll()
        canLoadMore = true
        lastUpdateTime = Date()

        if isLocalFeed {
            await loadLocalEpisodes()
        } else {
            // Load with conditional GET
            await loadFirstPageConditional()
        }
    }
    
    /// Loads the first page using conditional GET
    private func loadFirstPageConditional() async {
        guard !isLoadingPage else { return }
        
        isLoadingPage = true
        state = .loading
        
        let taskID = "load-first-page-conditional"
        
        let task = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                // Try conditional fetch first
                if let result = try await self.episodeService.fetchPageConditional(
                    showID: self.podcastID,
                    cursor: nil,
                    limit: self.pageLimit,
                    etag: self.currentEtag,
                    lastModified: self.currentLastModified
                ) {
                    // Feed was modified, process new episodes
                    let (episodes, nextCursor, newEtag, newLastModified) = result
                    
                    await MainActor.run {
                        self.currentEtag = newEtag
                        self.currentLastModified = newLastModified
                        self.currentCursor = nextCursor
                        self.canLoadMore = nextCursor != nil
                        
                        // Convert to EpisodeWithPlaybackState
                        let episodesWithState = episodes.map { episode in
                            EpisodeWithPlaybackState(
                                episode: episode,
                                playbackState: PlaybackState(episodeID: episode.id, position: 0.0, finished: false)
                            )
                        }
                        
                        self.allEpisodes = episodesWithState
                        self.applyFiltersAndSort()
                        self.state = .loaded
                        self.isLoadingPage = false
                        
                    }
                } else {
                    // 304 Not Modified - use existing episodes
                    await MainActor.run {
                        self.state = .loaded
                        self.isLoadingPage = false
                    }
                }
                
            } catch {
                await MainActor.run {
                    self.state = .error("Failed to load episodes: \(error.localizedDescription)")
                    self.isLoadingPage = false
                }
            }
        }
        
        taskManager.registerTask(task, id: taskID)
        await task.value
    }
    
    // MARK: - Phase 4: Pagination API
    
    /// Loads the first page of episodes using pagination
    func loadFirstPage() async {
        guard !isLoadingPage else { return }

        // Reset pagination state
        currentCursor = nil
        allEpisodes.removeAll()
        displayedEpisodes.removeAll()
        canLoadMore = true
        if isLocalFeed {
            await loadLocalEpisodes()
        } else {
            await loadNextPage()
        }
    }

    /// Loads the next page of episodes with single cancellable Task
    func loadNextPage() async {
        guard canLoadMore && !isLoadingPage else { return }
        
        // Cancel any existing pagination task
        paginationTask?.cancel()
        
        isLoadingPage = true
        state = .loading

        // Handle local feeds by loading all episodes from repository
        if isLocalFeed {
            paginationTask = Task { @MainActor in
                do {
                    let episodes = try await episodeRepository.fetchAllEpisodes(for: podcastID, ignoreCache: false)
                    await handlePageLoaded(episodes, nextCursor: nil)
                } catch {
                    await handlePaginationError(error)
                }
            }
            return
        }

        // Create single cancellable Task for pagination
        paginationTask = Task { @MainActor in
            do {
                // Use EpisodeService.fetchPage with timeout
                let (episodes, nextCursor) = try await episodeService.fetchPage(
                    showID: podcastID,
                    cursor: currentCursor,
                    limit: pageLimit
                )
                
                // Check for cancellation
                try Task.checkCancellation()
                
                // Convert episodes to EpisodeWithPlaybackState
                let episodesWithState = episodes.map { episode in
                    EpisodeWithPlaybackState(
                        episode: episode,
                        playbackState: PlaybackState(
                            episodeID: episode.id,
                            position: 0,
                            finished: false,
                            updatedAt: Date()
                        )
                    )
                }
                
                // Update state
                await handlePageLoaded(episodesWithState, nextCursor: nextCursor)
                
            } catch {
                // Handle pagination error
                await handlePaginationError(error)
            }
        }
    }
    
    /// Stops pagination and cancels current task
    private func stopPagination() {
        paginationTask?.cancel()
        paginationTask = nil
        isLoadingPage = false
    }
    
    /// Handles successfully loaded page
    private func handlePageLoaded(_ episodes: [EpisodeWithPlaybackState], nextCursor: String?) async {
        // Update cursor and pagination state
        currentCursor = nextCursor
        canLoadMore = nextCursor != nil
        isLoadingPage = false
        
        // Add episodes to collection
        allEpisodes.append(contentsOf: episodes)
        
        // Apply filters and update UI
        applyFiltersAndSort()
        
        // Update state
        state = .loaded
        
        // Update progress
        streamProgress = "Loaded \(allEpisodes.count) episodes"
    }
    
    /// Handles pagination error
    private func handlePaginationError(_ error: Error) async {
        isLoadingPage = false
        let friendlyMessage = getFriendlyErrorMessage(error)
        state = .error(friendlyMessage)
        streamProgress = "Error: \(friendlyMessage)"
        
        errorManager.showError(friendlyMessage) { [weak self] in
            Task { @MainActor in
                await self?.loadNextPage()
            }
        }
    }

    /// Loads all episodes from the repository for local podcasts
    private func loadLocalEpisodes() async {
        paginationTask?.cancel()
        isLoadingPage = true
        state = .loading

        paginationTask = Task { @MainActor in
            do {
                let episodes = try await episodeRepository.fetchAllEpisodes(for: podcastID, ignoreCache: false)
                await handlePageLoaded(episodes, nextCursor: nil)
            } catch {
                await handlePaginationError(error)
            }
        }
    }

    // MARK: - Phase 2: Streaming API (Legacy Support)
    
    /// Starts streaming episodes from RSS feed using new EpisodeService
    func startStreamingEpisodes() {
        guard !isStreaming else { return }
        
        // Reset state for new stream
        resetStreamingState()
        
        // Create cancellable Task on MainActor
        streamingTask = Task { @MainActor in
            do {
                // Stream episodes using AsyncSequence
                for try await episode in episodeService.streamEpisodes(from: feedURL, podcastID: podcastID) {
                    // Check for cancellation
                    try Task.checkCancellation()
                    
                    // Handle streamed episode
                    await handleStreamedEpisode(episode)
                }
                
                // Stream completed successfully
                await handleStreamingCompletion()
                
            } catch {
                // Handle streaming error
                await handleStreamingError(error)
            }
        }
    }
    
    /// Stops the current streaming operation
    func stopStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
        stopUpdateTimer()
        flushPendingEpisodes()
    }
    
    /// Refreshes episodes by restarting the stream
    func refreshEpisodes() {
        stopStreaming()
        startStreamingEpisodes()
    }
    
    // MARK: - Phase 2: Streaming Helpers
    
    private func resetStreamingState() {
        state = .loading
        isStreaming = true
        episodeCount = 0
        streamProgress = "Starting stream..."
        allEpisodes.removeAll()
        displayedEpisodes.removeAll()
        pendingEpisodes.removeAll()
        startUpdateTimer()
    }
    
    private func handleStreamedEpisode(_ episode: Episode) async {
        episodeCount += 1
        
        // Convert to EpisodeWithPlaybackState
        let episodeWithState = EpisodeWithPlaybackState(
            episode: episode,
            playbackState: PlaybackState(
                episodeID: episode.id,
                position: 0,
                finished: false,
                updatedAt: Date()
            )
        )
        
        // Add to pending episodes for throttled updates
        pendingEpisodes.append(episodeWithState)
        streamProgress = "Loaded \(episodeCount) episodes..."
        
        // Flush if batch size reached (5 episodes)
        if pendingEpisodes.count >= batchSize {
            flushPendingEpisodes()
        }
    }
    
    private func handleStreamingCompletion() async {
        isStreaming = false
        canLoadMore = false
        state = .loaded
        streamProgress = "Completed: \(episodeCount) episodes"
        
        // Flush any remaining episodes
        flushPendingEpisodes()
        stopUpdateTimer()
    }
    
    private func handleStreamingError(_ error: Error) async {
        isStreaming = false
        let friendlyMessage = getFriendlyErrorMessage(error)
        state = .error(friendlyMessage)
        streamProgress = "Error: \(friendlyMessage)"
        
        // Flush any pending episodes before showing error
        flushPendingEpisodes()
        stopUpdateTimer()
        
        errorManager.showError(friendlyMessage) { [weak self] in
            self?.refreshEpisodes()
        }
    }
    
    // MARK: - Phase 2: Throttled UI Updates (every 5 items or 0.2s)
    
    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateThrottleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flushPendingEpisodes()
            }
        }
    }
    
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func flushPendingEpisodes() {
        guard !pendingEpisodes.isEmpty else { return }
        
        // Add pending episodes to all episodes
        allEpisodes.append(contentsOf: pendingEpisodes)
        pendingEpisodes.removeAll()
        
        // Apply filters and sort to update displayed episodes
        applyFiltersAndSort()
    }
    
    // MARK: - Phase 4: Diffable Snapshots for Page Merging
    
    /// Applies filters and sorting with diffable snapshot-like behavior
    /// Provides smooth UI updates when merging pages
    internal func applyFiltersAndSort() {
        // Create snapshot of current state
        let previousEpisodes = displayedEpisodes
        
        var filtered = allEpisodes
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { $0.episode.title.localizedCaseInsensitiveContains(searchText) }
        }
        
        // Apply content filter
        switch filterType {
        case .unplayed:
            filtered = filtered.filter { !$0.playbackState.finished }
        case .played:
            filtered = filtered.filter { $0.playbackState.finished }
        default:
            break
        }
        
        // Apply sort order
        switch sortOrder {
        case .newestFirst:
            filtered.sort(by: { ($0.episode.publishedDate ?? Date.distantPast) > ($1.episode.publishedDate ?? Date.distantPast) })
        case .oldestFirst:
            filtered.sort(by: { ($0.episode.publishedDate ?? Date.distantPast) < ($1.episode.publishedDate ?? Date.distantPast) })
        }
        
        // Create diffable-like update
        let newEpisodes = filtered
        
        // Calculate changes (simplified diffable snapshot behavior)
        let addedEpisodes = newEpisodes.filter { newEpisode in
            !previousEpisodes.contains { $0.id == newEpisode.id }
        }
        
        let removedEpisodes = previousEpisodes.filter { oldEpisode in
            !newEpisodes.contains { $0.id == oldEpisode.id }
        }
        
        // Log changes for debugging
        if !addedEpisodes.isEmpty || !removedEpisodes.isEmpty {
        }
        
        // Apply the new snapshot
        self.displayedEpisodes = newEpisodes
    }
    
    // MARK: - Internal Methods (accessible from extensions)
    internal func setupBindings() {
        // Setup search text debouncing
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.applyFiltersAndSort()
            }
            .store(in: &cancellables)
    }
    
    /// Get user-friendly error message
    nonisolated private func getFriendlyErrorMessage(_ error: Error) -> String {
        if error is CancellationError {
            return "Operation was cancelled"
        }
        
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return "No internet connection. Please check your network and try again."
        case NSURLErrorTimedOut:
            return "Request timed out. The server might be slow to respond."
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return "Cannot connect to server. Please try again later."
        case NSURLErrorNetworkConnectionLost:
            return "Network connection lost. Please check your connection and retry."
        default:
            return "Failed to load episodes: \(error.localizedDescription)"
        }
    }
}

// MARK: - Supporting Enums

extension ShowEpisodesViewModel {
    
    enum EpisodeSortOrder: String, CaseIterable, Identifiable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        
        var id: String { self.rawValue }
    }
    
    enum EpisodeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case unplayed = "Unplayed"
        case played = "Played"
        
        var id: String { self.rawValue }
    }
}