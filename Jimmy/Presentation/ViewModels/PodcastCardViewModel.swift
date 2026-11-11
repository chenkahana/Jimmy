import Foundation
import Combine
import os

@MainActor
class PodcastCardViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "PodcastCardViewModel")
    @Published var episodeCount: Int = 0
    @Published var unplayedCount: Int = 0
    
    private let podcastID: UUID
    private let episodeRepository: EpisodeRepositoryProtocol
    private let playbackStateRepository: PlaybackStateRepositoryProtocol
    
    // Caching to prevent repeated expensive queries
    private var hasLoadedData = false
    private var lastLoadTime: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    init(
        podcastID: UUID,
        episodeRepository: EpisodeRepositoryProtocol = DIContainer.shared.episodeRepository,
        playbackStateRepository: PlaybackStateRepositoryProtocol = DIContainer.shared.playbackStateRepository
    ) {
        self.podcastID = podcastID
        self.episodeRepository = episodeRepository
        self.playbackStateRepository = playbackStateRepository
    }
    
    /// Load data only if needed (not already loaded or cache expired)
    func loadDataIfNeeded() async {
        // Check if we need to load data
        let now = Date()
        if hasLoadedData,
           let lastLoad = lastLoadTime,
           now.timeIntervalSince(lastLoad) < cacheValidityDuration {
            return // Data is still fresh
        }
        
        await loadData()
    }
    
    /// Force load data (ignoring cache)
    func loadData() async {
        do {
            // Use cached data when possible to avoid expensive queries
            let episodes = (try? await episodeRepository.fetchAllEpisodes(for: podcastID, ignoreCache: false)) ?? []
            self.episodeCount = episodes.count
            
            // Optimize unplayed count calculation
            var unplayed = 0
            for episode in episodes.prefix(20) { // Only check first 20 episodes for performance
                let state = try? await playbackStateRepository.fetchPlaybackState(for: episode.id)
                if state?.finished != true { // Treat nil as unplayed
                    unplayed += 1
                }
            }
            self.unplayedCount = unplayed
            
            // Update cache state
            hasLoadedData = true
            lastLoadTime = Date()
        } catch {
            // Handle error silently to avoid UI disruption during scrolling
            Self.logger.error("Failed to load podcast card data: \(error)")
        }
    }
    
    /// Reset cache (useful when data changes)
    func invalidateCache() {
        hasLoadedData = false
        lastLoadTime = nil
    }
} 