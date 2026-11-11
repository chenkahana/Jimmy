import Foundation
import Combine

/// Enhanced episode repository that supports streaming episode loading.
/// This extends the existing repository pattern to include streaming capabilities,
/// solving timeout and UI blocking issues while maintaining data persistence.
final class StreamingEpisodeRepository: EpisodeRepositoryProtocol {
    
    private let baseRepository: GRDBEpisodeRepository
    private let streamingService = StreamingEpisodeService.shared
    
    // MARK: - Initialization
    
    init(baseRepository: GRDBEpisodeRepository) {
        self.baseRepository = baseRepository
    }
    
    // MARK: - EpisodeRepositoryProtocol Conformance
    
    func fetchPage(podcastID: UUID, cursor: String?, limit: Int, ignoreCache: Bool) async throws -> ([EpisodeWithPlaybackState], nextCursor: String?) {
        // Delegate to base repository for pagination
        return try await baseRepository.fetchPage(podcastID: podcastID, cursor: cursor, limit: limit, ignoreCache: ignoreCache)
    }
    
    func fetchEpisodes(for podcastID: UUID, ignoreCache: Bool) async throws -> [EpisodeWithPlaybackState] {
        // For regular episode fetching, delegate to base repository
        return try await baseRepository.fetchEpisodes(for: podcastID, ignoreCache: ignoreCache)
    }
    
    func fetchAllEpisodes(for podcastID: UUID, ignoreCache: Bool) async throws -> [EpisodeWithPlaybackState] {
        // For all episodes, delegate to base repository
        return try await baseRepository.fetchAllEpisodes(for: podcastID, ignoreCache: ignoreCache)
    }
    
    func fetchEpisode(by episodeID: UUID) async throws -> EpisodeWithPlaybackState? {
        // Delegate to base repository
        return try await baseRepository.fetchEpisode(by: episodeID)
    }
    
    func saveEpisodes(_ episodes: [EpisodeWithPlaybackState], for podcastID: UUID) async throws {
        // Delegate saving to base repository
        try await baseRepository.saveEpisodes(episodes, for: podcastID)
    }
    
    func isStale(podcastID: UUID) -> Bool {
        // Delegate to base repository
        return baseRepository.isStale(podcastID: podcastID)
    }
    
    var episodeChangesPublisher: AnyPublisher<CleanEpisodeChanges, Never> {
        // Delegate to base repository
        return baseRepository.episodeChangesPublisher
    }
    
    // MARK: - Streaming-Specific Methods
    
    /// Streams episodes from RSS feed and saves them incrementally to the database
    /// This solves timeout issues by processing episodes as they arrive
    /// - Parameters:
    ///   - feedURL: RSS feed URL to stream from
    ///   - podcastID: ID of the podcast
    ///   - progressHandler: Called for each episode as it's processed
    /// - Returns: Final count of episodes processed
    func streamAndSaveEpisodes(
        from feedURL: URL,
        podcastID: UUID,
        progressHandler: ((Episode, Int) -> Void)? = nil
    ) async throws -> Int {
        
        var episodeCount = 0
        var episodesToSave: [Episode] = []
        let batchSize = 10 // Save episodes in batches for better performance
        
        // Stream episodes and save them incrementally
        for try await result in streamingService.streamEpisodes(from: feedURL, podcastID: podcastID) {
            switch result {
            case .episode(let episode):
                episodesToSave.append(episode)
                episodeCount += 1
                
                // Call progress handler
                progressHandler?(episode, episodeCount)
                
                // Save in batches to avoid memory buildup and provide incremental persistence
                if episodesToSave.count >= batchSize {
                    try await saveBatch(episodesToSave, podcastID: podcastID, batchNumber: episodeCount / batchSize)
                    episodesToSave.removeAll()
                }
                
            case .metadata(_):
                // Metadata could be used to update podcast info if needed
                break
                
            case .error(let error):
                // Save any remaining episodes before throwing error
                if !episodesToSave.isEmpty {
                    try await saveBatch(episodesToSave, podcastID: podcastID, batchNumber: -1)
                }
                
                throw error
                
            case .completed(_):
                // Save any remaining episodes
                if !episodesToSave.isEmpty {
                    try await saveBatch(episodesToSave, podcastID: podcastID, batchNumber: -1)
                }
                
                break
            }
        }
        
        return episodeCount
    }
    
    /// Creates a streaming task that updates episodes in real-time
    /// This is useful for ViewModels that need live updates during streaming
    /// - Parameters:
    ///   - feedURL: RSS feed URL to stream from
    ///   - podcastID: ID of the podcast
    ///   - onEpisodeReceived: Called when each episode is received and saved
    ///   - onError: Called if streaming fails
    ///   - onCompleted: Called when streaming completes
    /// - Returns: Cancellable task
    func createStreamingTask(
        feedURL: URL,
        podcastID: UUID,
        onEpisodeReceived: @escaping @MainActor (EpisodeWithPlaybackState, Int) -> Void,
        onError: @escaping @MainActor (Error) -> Void,
        onCompleted: @escaping @MainActor (Int) -> Void
    ) -> Task<Void, Never> {
        
        return Task {
            do {
                let totalEpisodes = try await streamAndSaveEpisodes(
                    from: feedURL,
                    podcastID: podcastID
                ) { episode, count in
                    // Convert episode to EpisodeWithPlaybackState and notify on main thread
                    let episodeWithState = EpisodeWithPlaybackState(
                        episode: episode,
                        playbackState: PlaybackState(
                            episodeID: episode.id,
                            position: 0,
                            finished: false,
                            updatedAt: Date()
                        )
                    )
                    
                    Task { @MainActor in
                        onEpisodeReceived(episodeWithState, count)
                    }
                }
                
                await MainActor.run {
                    onCompleted(totalEpisodes)
                }
                
            } catch {
                await MainActor.run {
                    onError(error)
                }
            }
        }
    }
    
    /// Refreshes episodes for a podcast using streaming
    /// This replaces the traditional "fetch all then update" approach
    /// - Parameters:
    ///   - feedURL: RSS feed URL
    ///   - podcastID: ID of the podcast
    ///   - forceRefresh: Whether to ignore cached data
    /// - Returns: Number of new/updated episodes
    func refreshEpisodesStreaming(
        from feedURL: URL,
        podcastID: UUID,
        forceRefresh: Bool = false
    ) async throws -> Int {
        
        // Get existing episodes to compare
        let existingEpisodes = try await fetchAllEpisodes(for: podcastID, ignoreCache: false)
        let existingTitles = Set(existingEpisodes.map { $0.episode.title })
        
        var newEpisodeCount = 0
        
        // Stream and save new episodes
        let totalEpisodes = try await streamAndSaveEpisodes(
            from: feedURL,
            podcastID: podcastID
        ) { episode, count in
            // Count new episodes
            if !existingTitles.contains(episode.title) {
                newEpisodeCount += 1
            }
        }
        
        return newEpisodeCount
    }
    
    // MARK: - Phase 5: Conditional GET Support
    
    func fetchPageConditional(
        podcastID: UUID,
        cursor: String?,
        limit: Int,
        etag: String?,
        lastModified: String?
    ) async throws -> ([EpisodeWithPlaybackState], nextCursor: String?, newEtag: String?, newLastModified: String?)? {
        // Delegate to base repository for conditional GET
        return try await baseRepository.fetchPageConditional(
            podcastID: podcastID,
            cursor: cursor,
            limit: limit,
            etag: etag,
            lastModified: lastModified
        )
    }
    
    // MARK: - Internal Methods
    
    internal func saveBatch(_ episodes: [Episode], podcastID: UUID, batchNumber: Int) async throws {
        guard !episodes.isEmpty else { return }
        
        
        // Convert episodes to EpisodeWithPlaybackState for saving
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
        
        // Save using base repository
        try await baseRepository.saveEpisodes(episodesWithState, for: podcastID)
        
    }
}

// MARK: - Factory Extension

extension DIContainer {
    /// Creates a streaming-enabled episode repository
    var streamingEpisodeRepository: StreamingEpisodeRepository {
        guard let grdbRepository = episodeRepository as? GRDBEpisodeRepository else {
            fatalError("StreamingEpisodeRepository requires GRDBEpisodeRepository")
        }
        return StreamingEpisodeRepository(baseRepository: grdbRepository)
    }
}

// MARK: - Convenience Extensions

extension StreamingEpisodeRepository {
    
    /// Convenience method to check if a podcast needs episode updates
    /// - Parameters:
    ///   - podcastID: ID of the podcast to check
    ///   - maxAge: Maximum age of episodes before considering refresh (default: 1 hour)
    /// - Returns: Whether the podcast needs episode updates
    func needsEpisodeUpdate(podcastID: UUID, maxAge: TimeInterval = 3600) async -> Bool {
        do {
            let episodes = try await fetchAllEpisodes(for: podcastID, ignoreCache: false)
            
            // If no episodes, definitely need update
            guard !episodes.isEmpty else { return true }
            
            // Check if the most recent episode is older than maxAge
            let mostRecentDate = episodes.compactMap { $0.episode.publishedDate }.max() ?? Date.distantPast
            let timeSinceLastEpisode = Date().timeIntervalSince(mostRecentDate)
            
            return timeSinceLastEpisode > maxAge
            
        } catch {
            return true // Assume update needed if we can't check
        }
    }
    
    /// Gets episode statistics for a podcast
    /// - Parameter podcastID: ID of the podcast
    /// - Returns: Episode statistics
    func getEpisodeStats(for podcastID: UUID) async -> EpisodeStats {
        do {
            let episodes = try await fetchAllEpisodes(for: podcastID, ignoreCache: false)
            
            let totalEpisodes = episodes.count
            let playedEpisodes = episodes.filter { $0.playbackState.finished }.count
            let inProgressEpisodes = episodes.filter { $0.playbackState.position > 0 && !$0.playbackState.finished }.count
            let unplayedEpisodes = totalEpisodes - playedEpisodes - inProgressEpisodes
            
            return EpisodeStats(
                total: totalEpisodes,
                played: playedEpisodes,
                inProgress: inProgressEpisodes,
                unplayed: unplayedEpisodes
            )
            
        } catch {
            return EpisodeStats(total: 0, played: 0, inProgress: 0, unplayed: 0)
        }
    }
}

// MARK: - Supporting Types

struct EpisodeStats {
    let total: Int
    let played: Int
    let inProgress: Int
    let unplayed: Int
    
    var playedPercentage: Double {
        guard total > 0 else { return 0.0 }
        return Double(played) / Double(total) * 100.0
    }
} 