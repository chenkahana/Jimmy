import Foundation
import Combine
import Observation
import os

/// Actor-based progress cache store that maintains real-time episode progress
/// and broadcasts updates to UI components for synchronized progress bars
@MainActor
final class ProgressCacheStore: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "ProgressCacheStore")
    static let shared = ProgressCacheStore()
    
    /// Map of episode ID to current playback position in seconds
    @Published private(set) var progressMap: [UUID: Double] = [:]
    
    /// Map of episode ID to current progress percentage (0.0 to 1.0)
    @Published private(set) var progressPercentageMap: [UUID: Double] = [:]
    
    private var cancellables = Set<AnyCancellable>()
    private let playbackStateRepository: PlaybackStateRepositoryProtocol
    
    /// Throttling to prevent excessive database writes
    private var lastPersistTime: Date = Date()
    private let persistThrottleInterval: TimeInterval = 2.0
    
    private init() {
        self.playbackStateRepository = DIContainer.shared.playbackStateRepository
        setupAudioPlayerSubscription()
        
        // CRITICAL FIX: Pre-populate cache with all episode progress on app launch
        Task.detached(priority: .utility) {
            await self.preloadAllEpisodeProgress()
        }
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Public API
    
    /// Get current progress position in seconds for an episode
    func getProgress(for episodeID: UUID) -> Double {
        return progressMap[episodeID] ?? 0.0
    }
    
    /// Get current progress percentage (0.0 to 1.0) for an episode
    func getProgressPercentage(for episodeID: UUID) -> Double {
        return progressPercentageMap[episodeID] ?? 0.0
    }
    
    /// Set progress for an episode (used for external updates)
    func setProgress(for episodeID: UUID, position: Double, duration: Double) {
        progressMap[episodeID] = position
        
        if duration > 0 {
            progressPercentageMap[episodeID] = min(1.0, max(0.0, position / duration))
        } else {
            progressPercentageMap[episodeID] = 0.0
        }
        
        // Throttled persistence to database
        throttledPersist(episodeID: episodeID, position: position)
    }
    
    /// Clear progress for an episode (when deleted or reset)
    func clearProgress(for episodeID: UUID) {
        progressMap.removeValue(forKey: episodeID)
        progressPercentageMap.removeValue(forKey: episodeID)
    }
    
    /// Check if an episode has progress data in the cache
    func hasProgress(for episodeID: UUID) -> Bool {
        return progressMap.keys.contains(episodeID)
    }
    
    /// Get the number of episodes with cached progress (for debugging)
    var cachedEpisodeCount: Int {
        return progressMap.count
    }
    
    /// Check if the progress cache has been initialized
    var isInitialized: Bool {
        return !progressMap.isEmpty || !progressPercentageMap.isEmpty
    }
    
    /// Mark episode as completed (progress = 100%)
    func markCompleted(for episodeID: UUID, duration: Double) {
        progressMap[episodeID] = duration
        progressPercentageMap[episodeID] = 1.0
        
        // Immediately persist completion
        Task.detached(priority: .utility) { [weak self] in
            await self?.persistProgress(episodeID: episodeID, position: duration)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupAudioPlayerSubscription() {
        // `Playback` is `@Observable`, not a Combine publisher — poll its state via an
        // observation loop instead of subscribing, the same pattern `AppModel` uses.
        observePlaybackPosition()

        // Listen for episode completion
        NotificationCenter.default.publisher(for: .episodeStatusUpdated)
            .sink { [weak self] notification in
                guard let episode = notification.object as? Episode,
                      episode.status.contains(.played) else { return }
                
                // Mark as completed in cache
                if let duration = episode.duration {
                    self?.markCompleted(for: episode.id, duration: duration)
                }
            }
            .store(in: &cancellables)
    }
    
    private func observePlaybackPosition() {
        withObservationTracking { [weak self] in
            _ = AppModel.current?.playback?.position
            _ = AppModel.current?.playback?.currentEpisode
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handlePlaybackPositionChange()
                self.observePlaybackPosition()
            }
        }
    }

    private func handlePlaybackPositionChange() {
        guard let playback = AppModel.current?.playback, let episodeID = playback.currentEpisode?.id else { return }
        let position = playback.position
        let duration = playback.duration ?? 0

        progressMap[episodeID] = position
        progressPercentageMap[episodeID] = duration > 0 ? min(1.0, max(0.0, position / duration)) : 0.0

        throttledPersist(episodeID: episodeID, position: position)
    }

    private func throttledPersist(episodeID: UUID, position: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastPersistTime) >= persistThrottleInterval else { return }
        
        lastPersistTime = now
        
        Task.detached(priority: .utility) { [weak self] in
            await self?.persistProgress(episodeID: episodeID, position: position)
        }
    }
    
    private func persistProgress(episodeID: UUID, position: Double) async {
        do {
            let state = PlaybackState(episodeID: episodeID, position: position, finished: false)
            try await playbackStateRepository.savePlaybackState(state)
        } catch {
            Self.logger.error("ProgressCacheStore: Failed to persist progress for episode \(episodeID): \(error)")
        }
    }
    
    /// Pre-load all episode progress from database into cache on app launch
    /// This ensures all episodes show their correct progress bars immediately
    private func preloadAllEpisodeProgress() async {
        Self.logger.info("ProgressCacheStore: Pre-loading all episode progress from database")
        
        do {
            // Fetch all playback states from database
            let allPlaybackStates = try await playbackStateRepository.fetchAllPlaybackStates()
            
            await MainActor.run {
                // Populate cache with all episode progress
                for playbackState in allPlaybackStates {
                    let episodeID = playbackState.episodeID
                    let position = playbackState.position
                    
                    // Set position in cache
                    self.progressMap[episodeID] = position
                    
                    // CRITICAL FIX: Set a reasonable default percentage based on position
                    // This prevents progress bars from showing 0% when we have position data
                    if position > 0 {
                        // Use a default duration estimate of 30 minutes (1800 seconds) for percentage calculation
                        // This will be corrected when actual episode duration is loaded
                        let estimatedDuration: Double = 1800
                        let estimatedPercentage = min(1.0, max(0.0, position / estimatedDuration))
                        self.progressPercentageMap[episodeID] = estimatedPercentage
                    } else {
                        self.progressPercentageMap[episodeID] = 0.0
                    }
                }
                
                Self.logger.info("ProgressCacheStore: Pre-loaded progress for \(allPlaybackStates.count) episodes")
                Self.logger.debug("Progress percentages will be corrected when episode durations are loaded")
            }
        } catch {
            Self.logger.error("ProgressCacheStore: Failed to pre-load episode progress: \(error)")
        }
    }
    
    /// Update progress percentage when episode duration becomes available
    func updateProgressPercentage(for episodeID: UUID, duration: Double) {
        guard duration > 0, let position = progressMap[episodeID] else { return }
        let newPercentage = min(1.0, max(0.0, position / duration))
        
        // Only update if the new percentage is significantly different to avoid UI flicker
        let currentPercentage = progressPercentageMap[episodeID] ?? 0.0
        if abs(newPercentage - currentPercentage) > 0.01 { // 1% threshold
            progressPercentageMap[episodeID] = newPercentage
            Self.logger.debug("Updated progress for episode \(episodeID): \(String(format: "%.1f", newPercentage * 100))%")
        }
    }
} 