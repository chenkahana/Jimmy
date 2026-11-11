import Foundation
import Combine
import os

/// ViewState enum for proper state management as required by newFlowVerification.md
enum ViewState: Equatable {
    case loading
    case loaded
    case error(String)
}

/// ViewModel for Episode List functionality following MVVM patterns
/// Phase 6: Enhanced with error handling, retry logic, and task management
@MainActor
class EpisodeListViewModel: ObservableObject, TaskManagedViewModel {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "EpisodeListViewModel")
    // MARK: - Published Properties
    @Published var episodes: [EpisodeWithPlaybackState] = []
    @Published var state: ViewState = .loaded
    @Published var rows: [EpisodeRowViewModel] = []
    
    // MARK: - Private Properties
    private let podcastID: UUID
    private let episodeRepository: EpisodeRepositoryProtocol
    private let playbackStateRepository: PlaybackStateRepositoryProtocol
    private var currentPage = 1
    private var canLoadMorePages = true
    private var isLoadingPage = false
    private var currentCursor: String? = nil
    private let pageLimit: Int = 20
    
    // MARK: - Phase 6: Error Handling & Task Management
    let taskManager = TaskCancellationManager()
    let errorManager = ErrorStateManager()
    private let retryManager = RetryManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(
        podcastID: UUID,
        episodeRepository: EpisodeRepositoryProtocol = DIContainer.shared.episodeRepository,
        playbackStateRepository: PlaybackStateRepositoryProtocol = DIContainer.shared.playbackStateRepository
    ) {
        self.podcastID = podcastID
        self.episodeRepository = episodeRepository
        self.playbackStateRepository = playbackStateRepository
        setupBindings()
    }
    
    // MARK: - TaskManagedViewModel Protocol
    
    func onViewAppear() async {
        if episodes.isEmpty {
            await loadInitialEpisodes()
        }
    }
    
    func onViewDisappear() async {
        taskManager.cancelAllTasks()
    }
    
    deinit {
        // Task cleanup handled by TaskManagedViewModel
    }
    
    // MARK: - Public Methods
    func loadInitialEpisodes() async {
        guard episodes.isEmpty else { return }
        await loadMoreEpisodes()
    }
    
    func loadMoreEpisodes() async {
        guard canLoadMorePages && !isLoadingPage else { return }
        
        isLoadingPage = true
        state = .loading
        
        let task = Task.managed(
            id: "load-episodes",
            manager: taskManager
        ) {
            do {
                // PERFORMANCE FIX: Use direct repository call instead of complex merge heap
                // This reduces loading time significantly for initial episode display
                let (newEpisodes, nextCursor) = try await self.episodeRepository.fetchPage(
                    podcastID: self.podcastID,
                    cursor: self.currentCursor,
                    limit: self.pageLimit,
                    ignoreCache: false // Use cache for faster loading
                )
                
                await MainActor.run {
                    if newEpisodes.isEmpty {
                        self.canLoadMorePages = false
                    } else {
                        // PERFORMANCE FIX: Batch UI updates to prevent stuttering
                        let startIndex = self.episodes.count
                        self.episodes.append(contentsOf: newEpisodes)
                        self.currentCursor = nextCursor
                        self.canLoadMorePages = newEpisodes.count >= self.pageLimit
                        self.currentPage += 1
                        
                        // Update progress cache for newly loaded episodes
                        let progressCache = DIContainer.shared.progressCacheStore
                        for episodeWithState in newEpisodes {
                            if let duration = episodeWithState.episode.duration, duration > 0 {
                                progressCache.updateProgressPercentage(for: episodeWithState.episode.id, duration: duration)
                            }
                        }
                        
                        self.updateRows()
                    }
                    self.state = .loaded
                    self.isLoadingPage = false
                }
                
            } catch {
                // Handle 304 Not Modified as success case
                if let fetchError = error as? FetchError, case .notModified = fetchError {
                    await MainActor.run {
                        self.state = .loaded
                        self.isLoadingPage = false
                    }
                    return
                }
                
                // For other errors, try with retry logic but with reduced timeout
                do {
                    try await self.retryManager.executeWithRetry(
                        operation: {
                            let (allEpisodes, nextCursor) = try await self.episodeRepository.fetchPage(
                                podcastID: self.podcastID, 
                                cursor: self.currentCursor, 
                                limit: self.pageLimit, 
                                ignoreCache: true // Force refresh on retry
                            )
                            
                            await MainActor.run {
                                if allEpisodes.isEmpty {
                                    self.canLoadMorePages = false
                                } else {
                                    self.episodes.append(contentsOf: allEpisodes)
                                    self.currentCursor = nextCursor
                                    self.canLoadMorePages = allEpisodes.count >= self.pageLimit
                                    self.currentPage += 1
                                    self.updateRows()
                                }
                                self.state = .loaded
                                self.isLoadingPage = false
                            }
                        },
                        shouldRetry: RetryManager.shouldRetryNetworkError
                    )
                } catch {
                    await MainActor.run {
                        let friendlyMessage = self.getFriendlyErrorMessage(error)
                        self.state = .error(friendlyMessage)
                        self.isLoadingPage = false
                        
                        // Show error with retry option
                        self.errorManager.showError(friendlyMessage) { [weak self] in
                            Task { await self?.loadMoreEpisodes() }
                        }
                    }
                }
            }
        }
        
        await task.value
    }
    
    /// REMOVED: Complex merge heap loading that was causing delays
    /// Now using direct repository calls for faster loading
    
    func refreshEpisodes() async {
        // Reset loading state and trigger EpisodeUpdateService reload
        isLoadingPage = false
        
        episodes.removeAll()
        currentPage = 1
        canLoadMorePages = true
        rows.removeAll()
        
        // Trigger background reload via EpisodeUpdateService
        await EpisodeUpdateService.shared.reload(podcastID: podcastID)
        
        await loadMoreEpisodes()
    }
    
    func deleteEpisode(_ episode: Episode) async {
        // Remove from local array
        episodes.removeAll { $0.id == episode.id }
        
        // Update cache if we have a valid podcast ID
        guard let podcastID = episode.podcastID else {
            Self.logger.warning("Cannot delete episode: missing podcast ID")
            return
        }
        
        do {
            // Get all episodes for this podcast
            let (allEpisodes, _) = try await episodeRepository.fetchPage(podcastID: podcastID, cursor: nil, limit: 100, ignoreCache: false)
            // Remove the deleted episode and save back
            let updatedEpisodes = allEpisodes.filter { $0.id != episode.id }
            try await episodeRepository.saveEpisodes(updatedEpisodes, for: podcastID)
        } catch {
            Self.logger.error("Failed to delete episode: \(error.localizedDescription)")
        }
    }
    
    func toggleFinished(for episodeWithState: EpisodeWithPlaybackState) async {
        var updatedState = episodeWithState.playbackState
        updatedState.finished.toggle()
        
        if let index = episodes.firstIndex(where: { $0.id == episodeWithState.id }) {
            episodes[index].playbackState = updatedState
        }
        
        // Update episode status for badge display
        if updatedState.finished {
            EpisodeService.shared.setEpisodePlayed(episodeWithState.episode)
        } else {
            // Remove played status when unmarking as finished
            var newStatus = episodeWithState.episode.status
            newStatus.remove(.played)
            EpisodeService.shared.updateEpisodeStatus(episodeWithState.episode, status: newStatus)
        }
        
        try? await playbackStateRepository.savePlaybackState(updatedState)
    }
    
    func markAllEpisodesAsPlayed(for podcastID: UUID) {
        // Update local state immediately
        for index in episodes.indices {
            if episodes[index].episode.podcastID == podcastID {
                var updatedEpisode = episodes[index]
                updatedEpisode.playbackState.finished = true
                episodes[index] = updatedEpisode
            }
        }
        
        // Update in background
        let _: Task<Void, Never> = Task.detached(priority: .utility) { [weak self] in
            await self?.updateAllEpisodesPlayedStatus(for: podcastID, played: true)
        }
    }
    
    func markAllEpisodesAsUnplayed(for podcastID: UUID) {
        // Update local state immediately
        for index in episodes.indices {
            if episodes[index].episode.podcastID == podcastID {
                var updatedEpisode = episodes[index]
                updatedEpisode.playbackState.finished = false
                episodes[index] = updatedEpisode
            }
        }
        
        // Update in background
        let _: Task<Void, Never> = Task.detached(priority: .utility) { [weak self] in
            await self?.updateAllEpisodesPlayedStatus(for: podcastID, played: false)
        }
    }
    
    func markEpisodeAsPlayed(_ episode: Episode, played: Bool) {
        // Update local state immediately
        if let index = episodes.firstIndex(where: { $0.id == episode.id }) {
            var updatedEpisode = episodes[index]
            updatedEpisode.playbackState.finished = played
            episodes[index] = updatedEpisode
        }
        
        // Update in background
        let _: Task<Void, Never> = Task.detached(priority: .utility) { [weak self] in
            await self?.updateEpisodePlayedStatus(episode, played: played)
        }
    }
    
    func markAsPlayed(_ episode: Episode) async {
        guard let podcastID = episode.podcastID else {
            Self.logger.warning("Cannot mark episode as played: missing podcastID")
            return
        }
        
        do {
            // Get all episodes for this podcast
            let (allEpisodes, _) = try await episodeRepository.fetchPage(podcastID: podcastID, cursor: nil, limit: 100, ignoreCache: false)
            
            // Find and update the specific episode
            guard let index = allEpisodes.firstIndex(where: { $0.episode.id == episode.id }) else { return }
            var updatedEpisodes = allEpisodes
            var updatedEpisodeWithPlayback = updatedEpisodes[index]
            updatedEpisodeWithPlayback.episode.played = true
            updatedEpisodes[index] = updatedEpisodeWithPlayback
            
            // Save back to repository
            try await episodeRepository.saveEpisodes(updatedEpisodes, for: podcastID)
            
            // Update local state
            if let localIndex = episodes.firstIndex(where: { $0.id == episode.id }) {
                episodes[localIndex].episode.played = true
            }
        } catch {
            Self.logger.error("Failed to mark episode as played: \(error)")
        }
    }
    
    func downloadEpisode(_ episode: Episode) async {
        guard let podcastID = episode.podcastID else {
            Self.logger.warning("Cannot download episode: missing podcastID")
            return
        }
        
        do {
            // Get all episodes for this podcast
            let (allEpisodes, _) = try await episodeRepository.fetchPage(podcastID: podcastID, cursor: nil, limit: 100, ignoreCache: false)
            
            // Find and update the specific episode
            guard let index = allEpisodes.firstIndex(where: { $0.episode.id == episode.id }) else { return }
            var updatedEpisodes = allEpisodes
            let updatedEpisodeWithPlayback = updatedEpisodes[index]
            // Mark as downloading or downloaded based on your download logic
            updatedEpisodes[index] = updatedEpisodeWithPlayback
            
            // Save back to repository
            try await episodeRepository.saveEpisodes(updatedEpisodes, for: podcastID)
        } catch {
            Self.logger.error("Failed to download episode: \(error)")
        }
    }
    
    func markAsUnplayed(at index: Int) {
        let _: Task<Void, Never> = Task {
            guard index < episodes.count else { return }
            if episodes[index].episode.podcastID == podcastID {
                episodes[index].episode.played = false
                
                do {
                    try await episodeRepository.saveEpisodes(episodes, for: podcastID)
                } catch {
                    Self.logger.error("Failed to save episode: \(error)")
                }
            }
        }
    }
    
    func toggleNewStatus(at index: Int) {
        let _: Task<Void, Never> = Task {
            do {
                let (allEpisodes, _) = try await episodeRepository.fetchPage(podcastID: podcastID, cursor: nil, limit: 100, ignoreCache: false)
                guard index < allEpisodes.count else { return }
                
                var updatedEpisodes = allEpisodes
                updatedEpisodes[index].episode.isNew.toggle()
                
                try await episodeRepository.saveEpisodes(updatedEpisodes, for: podcastID)
            } catch {
                Self.logger.error("Failed to save episode: \(error)")
            }
        }
    }
    
    func markAsPlayedAndRemove(at index: Int) {
        Task {
            do {
                let (allEpisodes, _) = try await episodeRepository.fetchPage(podcastID: podcastID, cursor: nil, limit: 100, ignoreCache: false)
                guard index < allEpisodes.count else { return }
                
                var updatedEpisodes = allEpisodes
                updatedEpisodes[index].episode.played = true
                
                try await episodeRepository.saveEpisodes(updatedEpisodes, for: podcastID)
            } catch {
                Self.logger.error("Failed to save episode: \(error)")
            }
        }
    }
    
    func markAsUnplayedAndAdd(at index: Int) {
        Task {
            do {
                let (allEpisodes, _) = try await episodeRepository.fetchPage(podcastID: podcastID, cursor: nil, limit: 100, ignoreCache: false)
                guard index < allEpisodes.count else { return }
                
                var updatedEpisodes = allEpisodes
                updatedEpisodes[index].episode.played = false
                
                try await episodeRepository.saveEpisodes(updatedEpisodes, for: podcastID)
            } catch {
                Self.logger.error("Failed to save episode: \(error)")
            }
        }
    }
    
    func deleteEpisode(at index: Int) {
        Task {
            do {
                let (allEpisodes, _) = try await episodeRepository.fetchPage(podcastID: podcastID, cursor: nil, limit: 100, ignoreCache: false)
                guard index < allEpisodes.count else { return }
                
                var updatedEpisodes = allEpisodes
                updatedEpisodes.remove(at: index)
                
                try await episodeRepository.saveEpisodes(updatedEpisodes, for: podcastID)
            } catch {
                Self.logger.error("Failed to save episodes: \(error)")
            }
        }
    }
    
    // MARK: - Private Methods
    private func updateAllEpisodesPlayedStatus(for podcastID: UUID, played: Bool) async {
        do {
            let (allEpisodes, _) = try await episodeRepository.fetchPage(podcastID: podcastID, cursor: nil, limit: 100, ignoreCache: false)
            let updatedEpisodes = allEpisodes.map { episode in
                var updatedEpisode = episode
                updatedEpisode.playbackState.finished = played
                return updatedEpisode
            }
            try await episodeRepository.saveEpisodes(updatedEpisodes, for: podcastID)
        } catch {
            // Handle error silently for background operation
        }
    }
    
    private func updateEpisodePlayedStatus(_ episode: Episode, played: Bool) async {
        guard let podcastID = episode.podcastID else {
            Self.logger.warning("Cannot update episode played status: missing podcastID")
            return
        }
        
        do {
            let (allEpisodes, _) = try await episodeRepository.fetchPage(podcastID: podcastID, cursor: nil, limit: 100, ignoreCache: false)
            let updatedEpisodes = allEpisodes.map { ep in
                if ep.id == episode.id {
                    var updated = ep
                    updated.playbackState.finished = played
                    return updated
                }
                return ep
            }
            try await episodeRepository.saveEpisodes(updatedEpisodes, for: podcastID)
        } catch {
            // Handle error silently for background operation
        }
    }
    
    private func updateRows() {
        rows = episodes.map { episodeWithState in
            EpisodeRowViewModel(episodeWithState: episodeWithState)
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
            return "Request timed out. The server might be slow to respond."
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return "Cannot connect to server. Please try again later."
        case NSURLErrorNetworkConnectionLost:
            return "Network connection lost. Please check your connection and retry."
        default:
            return "Failed to load episodes: \(error.localizedDescription)"
        }
    }
    
    private func setupBindings() {
        // Listen for episode status updates
        NotificationCenter.default.publisher(for: .episodeStatusUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let updatedEpisode = notification.object as? Episode else { return }
                self?.updateEpisodeStatus(updatedEpisode)
            }
            .store(in: &cancellables)
    }
    
    /// Update episode status in the episodes array
    private func updateEpisodeStatus(_ updatedEpisode: Episode) {
        // Update the episode in the episodes array
        if let index = episodes.firstIndex(where: { $0.episode.id == updatedEpisode.id }) {
            var updatedEpisodeWithState = episodes[index]
            updatedEpisodeWithState.episode = updatedEpisode
            episodes[index] = updatedEpisodeWithState
            updateRows()
        }
    }
}

/// Lightweight row view model for diffable lists
struct EpisodeRowViewModel: Identifiable {
    let id: UUID
    let title: String
    let duration: String
    let publishedDate: String
    let isPlayed: Bool
    let episodeWithState: EpisodeWithPlaybackState
    
    init(episodeWithState: EpisodeWithPlaybackState) {
        self.id = episodeWithState.episode.id
        self.title = episodeWithState.episode.title
        self.duration = Self.formatDuration(episodeWithState.episode.duration)
        self.publishedDate = Self.formatDate(episodeWithState.episode.publishedDate)
        self.isPlayed = episodeWithState.playbackState.finished
        self.episodeWithState = episodeWithState
    }
    
    private static func formatDuration(_ duration: TimeInterval?) -> String {
        guard let duration = duration else { return "Unknown" }
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private static func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
} 