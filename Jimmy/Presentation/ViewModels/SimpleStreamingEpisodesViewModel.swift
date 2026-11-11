import Foundation
import SwiftUI
import Combine
import os

/// Simple streaming ViewModel that solves the core UI blocking issue
/// Episodes appear immediately as they're parsed, no waiting for full download
/// Phase 6: Enhanced with retry logic, error handling, and proper task cancellation
@MainActor
final class SimpleStreamingEpisodesViewModel: ObservableObject, TaskManagedViewModel {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "SimpleStreamingEpisodesViewModel")
    
    // MARK: - Published Properties
    @Published var episodes: [EpisodeWithPlaybackState] = []
    @Published var isStreaming: Bool = false
    @Published var streamingProgress: String = ""
    @Published var errorMessage: String?
    
    // MARK: - Task Management (Phase 6)
    let taskManager = TaskCancellationManager()
    let errorManager = ErrorStateManager()
    private let retryManager = RetryManager.shared
    
    // MARK: - Private Properties
    private let podcastID: UUID
    private let feedURL: URL
    private let streamingService = SimpleStreamingEpisodeService.shared
    private let episodeRepository: EpisodeRepositoryProtocol
    private let playbackRepository: PlaybackStateRepositoryProtocol
    private let podcastRepository: PodcastRepositoryProtocol
    
    private var episodeCount = 0
    private var cancellables = Set<AnyCancellable>()
    
    // Throttling for UI updates
    private var lastUIUpdate = Date()
    private let uiUpdateThrottle: TimeInterval = 0.1 // Update UI at most every 100ms
    
    // MARK: - Initialization
    
    init(
        podcastID: UUID,
        feedURL: URL,
        episodeRepository: EpisodeRepositoryProtocol = DIContainer.shared.episodeRepository,
        playbackRepository: PlaybackStateRepositoryProtocol = DIContainer.shared.playbackStateRepository,
        podcastRepository: PodcastRepositoryProtocol = DIContainer.shared.podcastRepository
    ) {
        self.podcastID = podcastID
        self.feedURL = feedURL
        self.episodeRepository = episodeRepository
        self.playbackRepository = playbackRepository
        self.podcastRepository = podcastRepository
        
        // Listen for episode status updates
        setupNotificationListeners()
    }
    
    // MARK: - Notification Listeners
    
    private func setupNotificationListeners() {
        // Listen for episode status updates
        NotificationCenter.default.publisher(for: .episodeStatusUpdated)
            .compactMap { $0.object as? Episode }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedEpisode in
                self?.updateEpisodeStatus(updatedEpisode)
            }
            .store(in: &cancellables)
    }
    
    /// Update episode status in the local episodes array
    private func updateEpisodeStatus(_ updatedEpisode: Episode) {
        Self.logger.debug("SimpleStreamingEpisodesViewModel: Received episodeStatusUpdated for \(updatedEpisode.title) with status: \(String(updatedEpisode.status.rawValue))")
        
        // Find and update the episode in our local array
        if let index = episodes.firstIndex(where: { $0.episode.id == updatedEpisode.id }) {
            Self.logger.debug("SimpleStreamingEpisodesViewModel: Found episode at index \(index), updating status")
            
            // Create updated EpisodeWithPlaybackState
            let currentEpisodeWithState = episodes[index]
            
            // Update the playback state based on the new episode status
            let updatedPlaybackState = PlaybackState(
                episodeID: updatedEpisode.id,
                position: currentEpisodeWithState.playbackState.position,
                finished: updatedEpisode.status.contains(.played),
                updatedAt: Date()
            )
            
            let updatedEpisodeWithState = EpisodeWithPlaybackState(
                episode: updatedEpisode,
                playbackState: updatedPlaybackState
            )
            
            episodes[index] = updatedEpisodeWithState
            Self.logger.debug("SimpleStreamingEpisodesViewModel: Updated episode \(updatedEpisode.title) with new status: \(String(updatedEpisode.status.rawValue))")
        } else {
            Self.logger.debug("SimpleStreamingEpisodesViewModel: Episode \(updatedEpisode.title) not found in local episodes array")
        }
    }
    
    // MARK: - TaskManagedViewModel Protocol
    
    func onViewAppear() async {
        // Start streaming when view appears - but only if not already streaming
        if episodes.isEmpty && !isStreaming {
            loadWithCacheThenStream()
        }
    }
    
    func onViewDisappear() async {
        // Automatically handled by TaskManagedViewModel extension
        taskManager.cancelAllTasks()
    }
    
    deinit {
        // Clean up notification listeners
        cancellables.removeAll()
    }
    
    // MARK: - Public API
    
    /// Start streaming episodes from RSS feed with retry logic
    /// Phase 6: Enhanced with exponential backoff retry
    func startStreaming() {
        guard !isStreaming else { 
            return 
        }
        
        // Cancel any existing streaming
        taskManager.cancelGroup("streaming")
        
        // Reset state
        episodes.removeAll()
        episodeCount = 0
        errorMessage = nil
        errorManager.clearError()
        isStreaming = true
        streamingProgress = "Connecting to feed..."
        let _ = Task.managed(
            id: "main-streaming",
            group: "streaming",
            manager: taskManager
        ) {
            await self.performStreamingWithRetry()
        }
    }
    
    /// Perform streaming with retry logic
    private func performStreamingWithRetry() async {
        do {
            try await performStreaming()
            
            // Streaming completed successfully - ensure UI updates on main thread
            await MainActor.run {
            isStreaming = false
            streamingProgress = "Completed - \(episodeCount) episodes loaded"
            }
            
        } catch {
            // Handle 304 Not Modified as success case
            if let fetchError = error as? FetchError, case .notModified = fetchError {
                // 304 Not Modified means cached data is still valid
                await MainActor.run {
                isStreaming = false
                streamingProgress = "Episodes are up to date"
                }
                return
            }
            
            // For other errors, try with retry logic
            do {
                try await retryManager.executeWithRetry(
                    operation: { [weak self] in
                        guard let self = self else { throw CancellationError() }
                        try await self.performStreaming()
                    },
                    shouldRetry: RetryManager.shouldRetryNetworkError
                )
                
                // Streaming completed successfully after retry - ensure UI updates on main thread
                await MainActor.run {
                isStreaming = false
                streamingProgress = "Completed - \(episodeCount) episodes loaded"
                }
                
            } catch {
                // Handle streaming errors with user-friendly error UI - ensure UI updates on main thread
                await MainActor.run {
                isStreaming = false
                streamingProgress = "Failed to load episodes"
                
                // Show error with retry option
                let friendlyMessage = getFriendlyErrorMessage(error)
                errorManager.showError(friendlyMessage) { [weak self] in
                    self?.startStreaming()
                    }
                }
            }
        }
    }
    
    /// Core streaming logic (non-blocking)
    private func performStreaming() async throws {
        // This is the key: AsyncSequence that yields episodes as they're parsed
        let episodeStream = streamingService.streamEpisodes(from: feedURL, podcastID: podcastID)
        
        streamingProgress = "Streaming episodes..."
        
        // Collect episodes for batch saving
        var episodesToSave: [EpisodeWithPlaybackState] = []
        
        // Batching for UI updates
        var batch: [EpisodeWithPlaybackState] = []
        let batchSize = 5 // Update UI every 5 episodes for better performance

        // Process episodes as they arrive - NO WAITING!
        for try await episode in episodeStream {
            if Task.isCancelled { throw CancellationError() }
            
            // Load episode status from database using EpisodeService
            var finalEpisode = episode
            if let existingEpisode = try? await EpisodeService.shared.getEpisodeWithStatus(episode) {
                finalEpisode = existingEpisode
                // Only log when we actually find existing episodes (less common, more useful)
                let existingStatusStr = String(existingEpisode.status.rawValue)
                Self.logger.debug("Found existing episode \(episode.title.prefix(30)) with status: \(existingStatusStr)")
            } else {
                // Don't log every new episode - this is expected and creates log spam
                // print("🎯 New episode '\(episode.title.prefix(30))...' - no existing status")
            }
            
            // Fetch the actual playback state immediately for this episode
            let actualPlaybackState = (try? await playbackRepository.fetchPlaybackState(for: finalEpisode.id)) ??
                PlaybackState(episodeID: finalEpisode.id, position: 0, finished: false, updatedAt: Date())
            
            // Create a fully-formed object with the correct state from the start
            let episodeWithState = EpisodeWithPlaybackState(
                episode: finalEpisode,
                playbackState: actualPlaybackState
            )
            
            batch.append(episodeWithState)
            
            // When batch is full, update the UI
            if batch.count >= batchSize {
                await MainActor.run {
                    episodes.append(contentsOf: batch)
                    episodeCount += batch.count
                    streamingProgress = "Loaded \(episodeCount) episodes..."
                }
                batch.removeAll()
            }
            
            // Add to the complete list for saving later
            episodesToSave.append(episodeWithState)
        }
        
        // Append any remaining episodes from the last batch
        if !batch.isEmpty {
            await MainActor.run {
                episodes.append(contentsOf: batch)
                episodeCount += batch.count
                streamingProgress = "Loaded \(episodeCount) episodes..."
            }
        }
        
        // Episodes are already saved by the PodcastDetailView's fetchPodcastWithEpisodes() call
        // No need to save them again here - that was causing the foreign key constraint error
        // The UI streaming is just for display purposes
    }
    
    /// Cancel ongoing streaming
    func cancelStreaming() {
        taskManager.cancelGroup("streaming")
        isStreaming = false
        streamingProgress = "Cancelled"
        errorManager.clearError()
    }
    
    /// Refresh episodes by restarting the stream
    func refresh() {
        cancelStreaming()
        
        // Small delay to ensure cancellation is processed
        let _ = Task.managed(
            id: "refresh",
            manager: taskManager
        ) {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            await MainActor.run {
                self.startStreaming()
            }
        }
    }
    
    /// Load cached episodes first, then stream fresh ones (non-blocking)
    /// This provides immediate content while fresh data loads
    func loadWithCacheThenStream() {
        // Prevent multiple concurrent operations
        taskManager.cancelGroup("cache-then-stream")
        
        let _ = Task.managed(
            id: "cache-then-stream",
            group: "cache-then-stream",
            manager: taskManager
        ) {
            // 1. Load cached episodes immediately (no blocking)
            do {
                let cachedEpisodes = try await self.episodeRepository.fetchAllEpisodes(for: self.podcastID, ignoreCache: false)
                
                await MainActor.run {
                    if !cachedEpisodes.isEmpty && !self.isStreaming {
                        self.episodes = cachedEpisodes
                        self.streamingProgress = "Showing \(cachedEpisodes.count) cached episodes"
                    }
                }
            } catch {
                await MainActor.run {
                }
            }
            
            // 2. Start streaming fresh episodes (they'll be added progressively)
            await MainActor.run {
                // Only start streaming if not already in progress
                if !self.isStreaming {
                    self.startStreaming()
                }
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
            return "Request timed out. The podcast server might be slow to respond."
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return "Cannot connect to podcast server. Please try again later."
        case NSURLErrorNetworkConnectionLost:
            return "Network connection lost. Please check your connection and retry."
        default:
            return "Failed to load episodes: \(error.localizedDescription)"
        }
    }
}

// MARK: - Convenience Extensions

extension SimpleStreamingEpisodesViewModel {
    
    /// Whether there are any episodes to display
    var hasEpisodes: Bool {
        !episodes.isEmpty
    }
    
    /// Whether we should show loading indicator
    var shouldShowLoading: Bool {
        isStreaming && episodes.isEmpty
    }
    
    /// Whether we should show progress text
    var shouldShowProgress: Bool {
        isStreaming || !streamingProgress.isEmpty
    }
    
    /// Whether we should show error
    var shouldShowError: Bool {
        errorMessage != nil
    }
} 