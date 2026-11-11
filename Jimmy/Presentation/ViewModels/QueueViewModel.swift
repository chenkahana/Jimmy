import Foundation
import Combine
import os.log

struct QueueState: Equatable {
    var isLoading = false
    var errorMessage: String?
    var isDragging = false
}

/// ViewModel for Queue functionality following MVVM patterns
@MainActor
class QueueViewModel: ObservableObject {
    static let shared = QueueViewModel()
    
    // MARK: - Published Properties (exactly as per spec)
    @Published var episodes: [Episode] = []
    @Published var currentEpisode: Episode?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published private(set) var state = QueueState()
    
    // MARK: - Drag State
    @Published var draggedEpisode: Episode?
    @Published var isDragging: Bool = false
    
    // MARK: - Private Properties
    private let audioPlayerService: AudioPlayerService
    private let cacheService: EpisodeCacheService
    private let progressCache: ProgressCacheStore
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "Jimmy", category: "QueueViewModel")
    
    // MARK: - Rate Limiting for CPU Protection
    private var lastOperationTime: Date = Date()
    private let operationThrottleInterval: TimeInterval = 0.1 // Minimum 100ms between operations
    private let operationQueue = DispatchQueue(label: "queueOperations", qos: .userInitiated)
    private var pendingOperations = 0
    private let maxPendingOperations = 5
    private var reorderLatencyToken: InteractionLatencyTracker.Token?
    
    private init() {
        self.audioPlayerService = AudioPlayerService.shared
        self.cacheService = EpisodeCacheService.shared
        self.progressCache = DIContainer.shared.progressCacheStore
        setupBindings()
        
        // CRITICAL FIX: Wait for database to be ready before loading queue
        Task {
            await DatabaseManager.shared.waitForReady()
            logger.info("Database ready, loading queue")
            await loadQueue()
        }
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // Bind to audio player current episode
        audioPlayerService.$currentEpisode
            .assign(to: \.currentEpisode, on: self)
            .store(in: &cancellables)
        
        // Listen for episode status updates
        NotificationCenter.default.publisher(for: .episodeStatusUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let updatedEpisode = notification.object as? Episode else { return }
                self?.updateEpisodeStatus(updatedEpisode)
            }
            .store(in: &cancellables)
        
        queueRefreshPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshQueue()
            }
            .store(in: &cancellables)
        
        // Subscribe to real-time progress updates
        progressCache.$progressPercentageMap
            .sink { [weak self] _ in
                // Progress updates will automatically trigger UI refresh
                // through @Published episodes array when views re-render
            }
            .store(in: &cancellables)
    }

    private var queueRefreshPublisher: AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            NotificationCenter.default.publisher(for: .episodeAddedToQueue).map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: .episodeRemovedFromQueue).map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: .queueOrderChanged).map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: .queueNeedsRefresh).map { _ in () }.eraseToAnyPublisher()
        )
        .eraseToAnyPublisher()
    }
    
    /// Update episode status in the queue episodes array
    private func updateEpisodeStatus(_ updatedEpisode: Episode) {
        // Update the episode in the episodes array
        if let index = episodes.firstIndex(where: { $0.id == updatedEpisode.id }) {
            episodes[index] = updatedEpisode
        }
    }
    
    private func loadQueue() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.isLoading = true
                self.state.isLoading = true
                // Load queue from database
                let queuedEpisodes = try await DIContainer.shared.playbackStateRepository.fetchQueuedEpisodes()
                self.episodes = queuedEpisodes.map { $0.episode }
                self.state.isLoading = false
                self.logger.info("Loaded \(self.episodes.count) episodes from database queue")
            } catch {
                self.state.isLoading = false
                self.logger.error("Failed to load queue from database: \(error)")

                // Legacy fallback: Load from UserDefaults
                if let data = UserDefaults.standard.data(forKey: "episode_queue"),
                   let loadedEpisodes = try? JSONDecoder().decode([Episode].self, from: data) {
                    self.episodes = loadedEpisodes
                    self.logger.info("Loaded \(self.episodes.count) episodes from legacy UserDefaults")

                    // Migrate to database
                    Task.detached(priority: .utility) {
                        await self.migrateQueueToDatabase()
                    }
                }
            }
        }
    }

    /// Refresh the queue from database (used when notifications are received)
    private func refreshQueue() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let queuedEpisodes = try await DIContainer.shared.playbackStateRepository.fetchQueuedEpisodes()
                self.episodes = queuedEpisodes.map { $0.episode }
                self.logger.debug("Refreshed queue: \(self.episodes.count) episodes")
            } catch {
                self.state.errorMessage = error.localizedDescription
                self.logger.error("Failed to refresh queue: \(error)")
            }
        }
    }
    
    private func migrateQueueToDatabase() async {
        do {
            for (index, episode) in episodes.enumerated() {
                try await DIContainer.shared.playbackStateRepository.addToQueue(
                    episodeID: episode.id, 
                    position: index + 1
                )
            }
            logger.info("Migrated queue to database")
            // Clear legacy UserDefaults
            UserDefaults.standard.removeObject(forKey: "episode_queue")
        } catch {
            logger.error("Failed to migrate queue to database: \(error)")
        }
    }
    
    /// Persist the current in-memory episode order to the database.
    /// This replaces the previous no-op saveQueue() and ensures drag/drop,
    /// shuffle, clear, and other array mutations are actually persisted.
    private func persistQueueOrder() {
        let episodeIDs = episodes.map { $0.id }
        Task {
            do {
                try await DIContainer.shared.playbackStateRepository.reorderQueue(episodeIDs: episodeIDs)
                logger.info("Persisted queue order: \(episodeIDs.count) episodes")
            } catch {
                logger.error("Failed to persist queue order: \(error)")
            }

            await MainActor.run {
                if let reorderLatencyToken = self.reorderLatencyToken {
                    InteractionLatencyTracker.shared.end(reorderLatencyToken)
                    self.reorderLatencyToken = nil
                }
            }
        }
    }
    
    // MARK: - Computed Properties (exactly as per spec)
    var totalRemainingTime: String {
        let totalSeconds = episodes.reduce(0) { $0 + $1.remainingTime }
        let hours = Int(totalSeconds) / 3600
        let minutes = Int(totalSeconds) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    func index(of episode: Episode) -> Int? {
        episodes.firstIndex(where: { $0.id == episode.id })
    }
    
    // MARK: - Drag API (exactly as per spec)
    
    /// Begin drag operation for reordering
    func beginDrag(episode: Episode) {
        guard !episodes.isEmpty else { return }
        draggedEpisode = episode
        isDragging = true
        state.isDragging = true
    }
    
    /// Move episode during drag operation
    func moveEpisode(from originalIndex: Int, to newIndex: Int) {
        guard originalIndex != newIndex,
              originalIndex >= 0, originalIndex < episodes.count,
              newIndex >= 0, newIndex <= episodes.count else { return }

        if reorderLatencyToken == nil {
            reorderLatencyToken = InteractionLatencyTracker.shared.begin(.queueReorder, detail: "drag-reorder")
        }
        
        // CRITICAL: Ensure main thread updates for @Published properties
        Task { @MainActor in
            let episode = self.episodes[originalIndex]
            self.episodes.remove(at: originalIndex)
            let adjustedIndex = newIndex > originalIndex ? newIndex - 1 : newIndex
            self.episodes.insert(episode, at: adjustedIndex)
        }
    }
    
    /// End drag operation and persist changes
    func endDrag() {
        // CRITICAL: Ensure main thread updates for @Published properties
        Task { @MainActor in
            self.draggedEpisode = nil
            self.isDragging = false
            self.state.isDragging = false
            self.persistQueueOrder()
        }
    }
    
    // MARK: - Play API (exactly as per spec)
    
    /// Play episode and move to top of queue
    func play(episode: Episode) {
        guard episodes.contains(where: { $0.id == episode.id }) else {
            logger.error("Episode not found in queue")
            return
        }

        // Move to position 1 (now playing) via repository
        Task {
            do {
                try await DIContainer.shared.playbackStateRepository.moveInQueue(episodeID: episode.id, toPosition: 1)
            } catch {
                // If episode is already at position 1 or other expected error, just play it
                logger.warning("Could not move episode to position 1: \(error)")
            }
            await audioPlayerService.loadEpisode(episode, startPlaying: true)
        }
    }
    
    // MARK: - Swipe Actions API (exactly as per spec)
    
    /// Move episode to top (index 1, keeping currently playing at 0)
    func moveToTop(episode: Episode) {
        guard let currentIndex = index(of: episode), currentIndex > 1 else { return }
        
        Task {
            do {
                // Move to position 1 in database (position 1 = index 0 in UI)
                try await DIContainer.shared.playbackStateRepository.moveInQueue(episodeID: episode.id, toPosition: 1)
                
                // Note: UI will be updated via notification, no need to manually update episodes array
            } catch {
                logger.error("Failed to move episode to top: \(error)")
            }
        }
    }
    
    /// Move episode to bottom
    func moveToBottom(episode: Episode) {
        guard let currentIndex = index(of: episode), currentIndex < episodes.count - 1 else { return }
        
        Task {
            do {
                // Move to last position in database
                let lastPosition = episodes.count
                try await DIContainer.shared.playbackStateRepository.moveInQueue(episodeID: episode.id, toPosition: lastPosition)
                
                // Note: UI will be updated via notification, no need to manually update episodes array
            } catch {
                logger.error("Failed to move episode to bottom: \(error)")
            }
        }
    }
    
    /// Remove episode from queue
    func remove(episode: Episode) {
        Task {
            do {
                // Remove from database queue
                try await DIContainer.shared.playbackStateRepository.removeFromQueue(episodeID: episode.id)
                
                // Note: UI will be updated via notification, no need to manually update episodes array
                
                // Update episode status in background
                Task.detached(priority: .utility) {
                    EpisodeService.shared.removeEpisodeFromQueue(episode)
                }
            } catch {
                logger.error("Failed to remove episode from queue: \(error)")
            }
        }
    }
    
    /// Remove all episodes from a specific podcast (for unsubscribe)
    func removeEpisodesFromPodcast(podcastID: UUID) {
        let removedEpisodes = episodes.filter { $0.podcastID == podcastID }
        guard !removedEpisodes.isEmpty else { return }

        // Remove each episode from queue via repository, then refresh
        Task {
            for episode in removedEpisodes {
                do {
                    try await DIContainer.shared.playbackStateRepository.removeFromQueue(episodeID: episode.id)
                } catch {
                    logger.error("Failed to remove episode \(episode.id) from queue: \(error)")
                }
            }
            // Update episode status in background
            Task.detached(priority: .utility) {
                for episode in removedEpisodes {
                    EpisodeService.shared.removeEpisodeFromQueue(episode)
                }
            }
        }
    }
    
    // MARK: - Legacy Support (keeping existing public methods)
    
    /// Add episode to the END of the queue (standard "Add to Queue" behavior)
    func addEpisode(_ episode: Episode) async throws {
        guard !episodes.contains(where: { $0.id == episode.id }) else {
            throw QueueError.episodeAlreadyInQueue
        }
        
        // CRITICAL FIX: Get the max queue position to robustly determine the next position.
        let maxPosition = try await DIContainer.shared.playbackStateRepository.getMaxQueuePosition()
        let nextPosition = (maxPosition ?? 0) + 1
        
        // Add to database queue at the end
        try await DIContainer.shared.playbackStateRepository.addToQueue(episodeID: episode.id, position: nextPosition)
        
        // Update episode status in background
        Task.detached(priority: .utility) {
            EpisodeService.shared.setEpisodeQueued(episode)
        }
    }
    
    /// Add episode to position 2 (after currently playing) - "Play Next" behavior
    func addEpisodeToTop(_ episode: Episode) async throws {
        guard !episodes.contains(where: { $0.id == episode.id }) else {
            throw QueueError.episodeAlreadyInQueue
        }
        
        // CRITICAL FIX: "Play Next" means position 2 (after currently playing at position 1)
        // This will bump all other episodes down by 1
        try await DIContainer.shared.playbackStateRepository.addToQueue(episodeID: episode.id, position: 2)
        
        // Update episode status in background
        Task.detached(priority: .utility) {
            EpisodeService.shared.setEpisodeQueued(episode)
        }
    }
    
    /// Play episode immediately - "Play Now" behavior
    /// This replaces the currently playing episode and starts playback
    func playNow(_ episode: Episode) async {
        // Use AudioPlayerService which will handle the queue logic
        await audioPlayerService.loadEpisode(episode, startPlaying: true)
        
        // Update episode status in background
        Task.detached(priority: .utility) {
            EpisodeService.shared.setEpisodePlaying(episode)
        }
    }
    
    func removeEpisode(_ episode: Episode) async throws {
        // Remove from database queue
        try await DIContainer.shared.playbackStateRepository.removeFromQueue(episodeID: episode.id)
        
        // Note: UI will be updated via notification, no need to manually update episodes array
        
        // Update episode status in background
        Task.detached(priority: .utility) {
            EpisodeService.shared.removeEpisodeFromQueue(episode)
        }
    }
    
    func removeEpisode(at index: Int) async throws {
        guard index < episodes.count else {
            throw QueueError.invalidIndex
        }

        let episode = episodes[index]

        // Remove from database queue via repository
        try await DIContainer.shared.playbackStateRepository.removeFromQueue(episodeID: episode.id)

        // Update episode status in background
        Task.detached(priority: .utility) {
            EpisodeService.shared.removeEpisodeFromQueue(episode)
        }
    }
    
    func moveEpisode(from source: IndexSet, to destination: Int) {
        // CRITICAL: Ensure main thread updates for @Published properties
        Task { @MainActor in
            self.episodes.move(fromOffsets: source, toOffset: destination)
            self.persistQueueOrder()
        }
    }
    
    func playEpisode(_ episode: Episode) async {
        // CRITICAL: Ensure main thread updates for @Published properties
        await MainActor.run {
            self.errorMessage = nil
        }
        
        // Load episode with playback state restoration and start playing
        await audioPlayerService.loadEpisode(episode, startPlaying: true)
    }
    
    func playEpisode(at index: Int) async {
        guard index < episodes.count else { return }
        let episode = episodes[index]
        await playEpisode(episode)
    }
    
    func playNext() async {
        guard !episodes.isEmpty else { return }

        let nextEpisode = episodes[0]

        // Remove from queue via repository and play
        do {
            try await DIContainer.shared.playbackStateRepository.removeFromQueue(episodeID: nextEpisode.id)
        } catch {
            logger.error("Failed to remove next episode from queue: \(error)")
        }

        await playEpisode(nextEpisode)
    }
    
    func clearQueue() {
        let episodesToRemove = episodes
        Task {
            // Persist empty queue to database
            do {
                try await DIContainer.shared.playbackStateRepository.reorderQueue(episodeIDs: [])
            } catch {
                logger.error("Failed to clear queue in database: \(error)")
            }
            // Update episode statuses in background
            Task.detached(priority: .utility) {
                for episode in episodesToRemove {
                    EpisodeService.shared.removeEpisodeFromQueue(episode)
                }
            }
        }
    }
    
    func shuffleQueue() {
        // CRITICAL: Ensure main thread updates for @Published properties
        Task { @MainActor in
            self.episodes.shuffle()
            self.persistQueueOrder()
        }
    }
    
    /// Remove all played episodes from the queue
    func clearPlayedEpisodes() {
        let playedEpisodes = episodes.filter { $0.status.contains(.played) }
        guard !playedEpisodes.isEmpty else { return }

        Task {
            for episode in playedEpisodes {
                do {
                    try await DIContainer.shared.playbackStateRepository.removeFromQueue(episodeID: episode.id)
                } catch {
                    logger.error("Failed to remove played episode \(episode.id) from queue: \(error)")
                }
            }
            Task.detached(priority: .utility) {
                for episode in playedEpisodes {
                    EpisodeService.shared.removeEpisodeFromQueue(episode)
                }
            }
        }
    }

    func getNextEpisode() -> Episode? {
        return episodes.first
    }
    
    func removeCurrentEpisode() {
        guard !episodes.isEmpty else { return }
        let episode = episodes[0]
        Task {
            do {
                try await DIContainer.shared.playbackStateRepository.removeFromQueue(episodeID: episode.id)
            } catch {
                logger.error("Failed to remove current episode from queue: \(error)")
            }
        }
    }
    
    // MARK: - Legacy Computed Properties
    var queuedEpisodes: [Episode] { episodes }
    var isEmpty: Bool { episodes.isEmpty }
    var count: Int { episodes.count }
    
    var totalDuration: TimeInterval {
        episodes.reduce(0) { $0 + ($1.duration ?? 0) }
    }
    
    var formattedTotalDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = Int(totalDuration) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Supporting Types
enum QueueError: LocalizedError {
    case episodeAlreadyInQueue
    case invalidIndex
    case emptyQueue
    
    var errorDescription: String? {
        switch self {
        case .episodeAlreadyInQueue:
            return "Episode is already in the queue"
        case .invalidIndex:
            return "Invalid queue index"
        case .emptyQueue:
            return "Queue is empty"
        }
    }
} 
