import Foundation
import SwiftUI
import Combine

/// Enhanced ViewModel for displaying episodes with streaming support.
/// This solves timeout and UI blocking issues by:
/// 1. Using streaming episode service to load episodes progressively
/// 2. Updating UI incrementally as episodes arrive (no waiting for full download)
/// 3. Running all network operations off the main thread
/// 4. Supporting cancellation mid-stream
/// 5. Throttling UI updates for smooth performance
@MainActor
final class StreamingShowEpisodesViewModel: ObservableObject {
    
    // MARK: - Published UI State
    @Published var displayedEpisodes: [EpisodeWithPlaybackState] = []
    @Published var state: EpisodeViewState = .loaded
    @Published var searchText: String = ""
    @Published var sortOrder: EpisodeSortOrder = .newestFirst
    @Published var filterType: EpisodeFilter = .all
    @Published var isStreaming: Bool = false
    @Published var streamProgress: StreamProgress = StreamProgress()
    
    // MARK: - Public Properties
    var hasMoreEpisodes: Bool {
        return streamProgress.totalEpisodes == nil || displayedEpisodes.count < (streamProgress.totalEpisodes ?? 0)
    }
    
    // MARK: - Internal State (accessible from services)
    internal let podcast: Podcast
    internal let streamingService = StreamingEpisodeService.shared
    
    internal var allEpisodes: [EpisodeWithPlaybackState] = []
    internal var cancellables = Set<AnyCancellable>()
    internal var streamingTask: Task<Void, Never>?
    
    // UI update throttling
    private var pendingEpisodes: [EpisodeWithPlaybackState] = []
    private var updateTimer: Timer?
    private let updateThrottleInterval: TimeInterval = 0.2 // Update UI every 200ms
    private let batchSize: Int = 5 // Flush every 5 episodes
    private var lastFlushTime: Date = Date()
    
    // MARK: - Initialization
    init(podcast: Podcast) {
        self.podcast = podcast
        setupBindings()
    }
    
    deinit {
        // Note: Cannot call cleanup() here as it requires MainActor access
        // Cleanup will happen automatically when the object is deallocated
    }
    
    // MARK: - Public API
    
    /// Starts streaming episodes from the podcast's RSS feed
    /// This replaces the traditional "load all then display" approach
    func startStreamingEpisodes() {
        guard !isStreaming else {
            return
        }
        // Reset state for new stream
        resetStreamingState()
        
        // Create streaming task with proper cancellation support
        streamingTask = streamingService.createStreamingTask(
            feedURL: self.podcast.feedURL,
            podcastID: self.podcast.id,
            onEpisode: { [weak self] episode, count in
                self?.handleStreamedEpisode(episode, count: count)
            },
            onMetadata: { [weak self] metadata in
                self?.handlePodcastMetadata(metadata)
            },
            onError: { [weak self] error in
                self?.handleStreamingError(error)
            },
            onCompletion: { [weak self] totalEpisodes in
                self?.handleStreamingCompletion(totalEpisodes: totalEpisodes)
            }
        )
    }
    
    /// Stops the current streaming operation
    func stopStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
        
        // Flush any pending episodes
        flushPendingEpisodes()
    }
    
    /// Refreshes episodes by restarting the stream
    func refreshEpisodes() {
        stopStreaming()
        startStreamingEpisodes()
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // React to search, sort, and filter changes with debouncing
        Publishers.CombineLatest3($searchText, $sortOrder, $filterType)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in 
                self?.applyFiltersAndSort() 
            }
            .store(in: &cancellables)
    }
    
    internal func resetStreamingState() {
        state = .loading
        isStreaming = true
        streamProgress = StreamProgress()
        allEpisodes.removeAll()
        displayedEpisodes.removeAll()
        pendingEpisodes.removeAll()
        
        // Start UI update timer for throttling
        startUpdateTimer()
    }
    
    internal func handleStreamedEpisode(_ episode: Episode, count: Int) {
        // Convert to EpisodeWithPlaybackState (default unplayed state)
        let episodeWithState = EpisodeWithPlaybackState(
            episode: episode,
            playbackState: PlaybackState(
                episodeID: episode.id,
                position: 0,
                finished: false,
                updatedAt: Date()
            )
        )
        
        // Add to pending episodes for throttled UI updates
        pendingEpisodes.append(episodeWithState)
        
        // Update progress
        streamProgress.episodesReceived = count
        streamProgress.lastEpisodeTitle = episode.title
        // Flush if batch size reached
        if pendingEpisodes.count >= batchSize {
            flushPendingEpisodes()
        }
    }
    
    internal func handlePodcastMetadata(_ metadata: PodcastMetadata) {
        streamProgress.podcastTitle = metadata.title
    }
    
    internal func handleStreamingError(_ error: Error) {
        
        // Stop streaming and show error
        isStreaming = false
        state = .error(error.localizedDescription)
        
        // Flush any pending episodes before showing error
        flushPendingEpisodes()
        stopUpdateTimer()
    }
    
    internal func handleStreamingCompletion(totalEpisodes: Int) {
        
        // Update final state
        isStreaming = false
        streamProgress.totalEpisodes = totalEpisodes
        streamProgress.isCompleted = true
        state = .loaded
        
        // Flush any remaining pending episodes
        flushPendingEpisodes()
        stopUpdateTimer()
    }
    
    // MARK: - UI Update Throttling
    
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
        
        // Add pending episodes to main collection
        allEpisodes.append(contentsOf: pendingEpisodes)
        pendingEpisodes.removeAll()
        lastFlushTime = Date()
        
        // Apply current filters and sorting
        applyFiltersAndSort()
        
    }
    
    private func applyFiltersAndSort() {
        var filtered = allEpisodes
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { 
                $0.episode.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.episode.description?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Apply content filter
        switch filterType {
        case .unplayed:
            filtered = filtered.filter { !$0.playbackState.finished }
        case .played:
            filtered = filtered.filter { $0.playbackState.finished }
        case .all:
            break
        }
        
        // Apply sort order
        switch sortOrder {
        case .newestFirst:
            filtered.sort { 
                ($0.episode.publishedDate ?? Date.distantPast) > ($1.episode.publishedDate ?? Date.distantPast) 
            }
        case .oldestFirst:
            filtered.sort { 
                ($0.episode.publishedDate ?? Date.distantPast) < ($1.episode.publishedDate ?? Date.distantPast) 
            }
        }
        
        displayedEpisodes = filtered
    }
}

// MARK: - Supporting Types

/// Progress information for streaming episodes
struct StreamProgress {
    var episodesReceived: Int = 0
    var totalEpisodes: Int?
    var podcastTitle: String?
    var lastEpisodeTitle: String?
    var isCompleted: Bool = false
    
    var progressText: String {
        if let total = totalEpisodes {
            return "Loaded \(episodesReceived) of \(total) episodes"
        } else {
            return "Loading episodes... (\(episodesReceived) received)"
        }
    }
    
    var progressPercentage: Double {
        guard let total = totalEpisodes, total > 0 else { return 0.0 }
        return Double(episodesReceived) / Double(total)
    }
}

// MARK: - Supporting Enums (same as original)

extension StreamingShowEpisodesViewModel {
    
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

// MARK: - Convenience Methods

extension StreamingShowEpisodesViewModel {
    
    /// Checks if more episodes should be loaded based on scroll position
    /// In streaming mode, this is less relevant since episodes load automatically
    func checkForLoadMore(episode: EpisodeWithPlaybackState) {
        // In streaming mode, episodes are loaded automatically
        // This method is kept for compatibility with existing UI code
        if !isStreaming && hasMoreEpisodes {
            startStreamingEpisodes()
        }
    }
    
    /// Gets the current loading status text for UI display
    var loadingStatusText: String {
        if isStreaming {
            return streamProgress.progressText
        } else {
            switch state {
            case .loading:
                return "Preparing to load episodes..."
            default:
                return ""
            }
        }
    }
    
    /// Gets the current progress percentage for progress bars
    var loadingProgress: Double {
        return streamProgress.progressPercentage
    }
} 