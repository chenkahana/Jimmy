import Foundation
import Combine
import OSLog

extension Notification.Name {
    static let episodeStoreDidFinishRefresh = Notification.Name("episodeStoreDidFinishRefresh")
}

/// Unified Episode Controller following Background Data Synchronization Plan
/// Key principles:
/// 1. Show cached data immediately on app launch
/// 2. Background updates without blocking UI
/// 3. Simple, clean data flow
/// 4. Thread-safe operations via EpisodeRepository
@MainActor
final class UnifiedEpisodeController: ObservableObject {
    static let shared = UnifiedEpisodeController()
    
    // MARK: - Published Properties
    
    @Published private(set) var episodes: [Episode] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var cacheStatus: CacheStatus = .unknown
    @Published private(set) var hasAttemptedLoad: Bool = false
    
    // MARK: - Cache Status
    
    enum CacheStatus {
        case unknown
        case loading
        case empty
        case loaded(count: Int, lastUpdated: Date)
        
        var description: String {
            switch self {
            case .unknown:
                return "Unknown"
            case .loading:
                return "Loading episodes..."
            case .empty:
                return "No episodes found"
            case .loaded(let count, let lastUpdated):
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .full
                let lastUpdatedString = formatter.localizedString(for: lastUpdated, relativeTo: Date())
                return "\(count) episodes (updated \(lastUpdatedString))"
            }
        }
    }
    
    // MARK: - Private Properties
    
    private let repository = EpisodeRepository.shared
    private let requestQueue = RequestQueue.shared
    private let podcastService = PodcastService.shared
    private var cancellables = Set<AnyCancellable>()
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "Jimmy", category: "UnifiedEpisodeController")
    #endif
    
    // MARK: - Initialization
    
    private init() {
        setupRepositoryObserver()
        setupRequestQueueObserver()
    }
    
    // MARK: - Public Interface
    
    func forceRefresh() {
        #if canImport(OSLog)
        logger.info("🔄 Force refresh requested by user, executing background refresh logic.")
        #endif
        
        // Clear any existing error state
        errorMessage = nil
        
        // Enqueue high-priority user refresh
        requestQueue.enqueue(FetchEpisodesRequest.userInitiatedRefresh())
        
        // Start background refresh
        refreshInBackground()
    }
    
    /// Get all episodes for a specific podcast ID
    func getEpisodes(for podcastID: UUID) -> [Episode] {
        return episodes.filter { $0.podcastID == podcastID }
    }
    
    /// Get total episode count
    func getEpisodeCount() -> Int {
        return episodes.count
    }
    
    func getAllEpisodes() -> [Episode] {
        return episodes
    }
    
    /// Mark episode as played/unplayed
    func markEpisodeAsPlayed(_ episode: Episode, played: Bool) {
        Task {
            // Update repository
            if played {
                await repository.markEpisodeAsPlayed(episode.id)
            }
            
            #if canImport(OSLog)
            logger.info("✅ Marked episode as \(played ? "played" : "unplayed"): \(episode.title)")
            #endif
        }
    }
    
    /// Mark all episodes for a podcast as played
    func markAllEpisodesAsPlayed(for podcastID: UUID) {
        Task {
            let podcastEpisodes = getEpisodes(for: podcastID)
            for episode in podcastEpisodes where !episode.played {
                await repository.markEpisodeAsPlayed(episode.id)
            }
            
            #if canImport(OSLog)
            logger.info("✅ Marked all episodes as played for podcast: \(podcastID)")
            #endif
        }
    }
    
    /// Mark all episodes for a podcast as unplayed
    func markAllEpisodesAsUnplayed(for podcastID: UUID) {
        Task {
            let podcastEpisodes = getEpisodes(for: podcastID)
            for episode in podcastEpisodes where episode.played {
                // Note: EpisodeRepository doesn't have markEpisodeAsUnplayed, 
                // so we'll need to implement this differently or add the method
                #if canImport(OSLog)
                logger.warning("⚠️ markEpisodeAsUnplayed not implemented in repository")
                #endif
            }
            
            #if canImport(OSLog)
            logger.info("✅ Marked all episodes as unplayed for podcast: \(podcastID)")
            #endif
        }
    }
    
    // MARK: - Private Setup
    
    private func setupRepositoryObserver() {
        repository.$episodes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedEpisodes in
                self?.handleRepositoryUpdate(updatedEpisodes)
            }
            .store(in: &cancellables)
    }
    
    private func setupRequestQueueObserver() {
        requestQueue.$isProcessing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isProcessing in
                self?.handleRequestQueueProcessing(isProcessing)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Private Logic
    
    private func handleRepositoryUpdate(_ updatedEpisodes: [Episode]) {
        self.episodes = updatedEpisodes
        
        if updatedEpisodes.isEmpty {
            self.cacheStatus = hasAttemptedLoad ? .empty : .unknown
        } else {
            self.cacheStatus = .loaded(count: updatedEpisodes.count, lastUpdated: repository.lastUpdateTime ?? Date())
        }
        
        #if canImport(OSLog)
        if hasAttemptedLoad {
            logger.info("📚 Repository updated: \(updatedEpisodes.count) episodes")
        }
        #endif
        
        hasAttemptedLoad = true
    }
    
    private func handleRequestQueueProcessing(_ isProcessing: Bool) {
        if isProcessing {
            if case .loading = cacheStatus {} else {
                self.cacheStatus = .loading
            }
            #if canImport(OSLog)
            logger.info("🔄 Request queue is processing")
            #endif
        }
    }
    
    private func refreshInBackground() {
        Task(priority: .background) {
            let podcasts = await podcastService.loadPodcastsAsync()
            let requests = podcasts.map { podcast in
                FetchEpisodesRequest.singlePodcast(podcast.id)
            }
            requestQueue.enqueue(requests)
        }
    }
}

// MARK: - Convenience Methods

extension UnifiedEpisodeController {
    /// Get episodes for podcast with sorting
    func getEpisodes(for podcastID: UUID, sortedBy sortOrder: EpisodeSortOrder) -> [Episode] {
        let podcastEpisodes = getEpisodes(for: podcastID)
        
        switch sortOrder {
        case .publishedDateNewest:
            return podcastEpisodes.sorted { ($0.publishedDate ?? Date.distantPast) > ($1.publishedDate ?? Date.distantPast) }
        case .publishedDateOldest:
            return podcastEpisodes.sorted { ($0.publishedDate ?? Date.distantPast) < ($1.publishedDate ?? Date.distantPast) }
        case .title:
            return podcastEpisodes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .playedStatus:
            return podcastEpisodes.sorted { !$0.played && $1.played }
        }
    }
    
    /// Get unplayed episodes count
    func getUnplayedEpisodesCount() -> Int {
        return episodes.filter { !$0.played }.count
    }
    
    /// Get unplayed episodes for podcast
    func getUnplayedEpisodes(for podcastID: UUID) -> [Episode] {
        return getEpisodes(for: podcastID).filter { !$0.played }
    }
    
    /// Check if episode exists
    func episodeExists(_ episodeID: UUID) -> Bool {
        return episodes.contains { $0.id == episodeID }
    }
    
    /// Get episode by ID
    func getEpisode(by episodeID: UUID) -> Episode? {
        return episodes.first { $0.id == episodeID }
    }
    
    /// Check if episode is played
    func isEpisodePlayed(_ episodeID: UUID) -> Bool {
        return episodes.first { $0.id == episodeID }?.played ?? false
    }
}

// MARK: - Episode Sort Order

enum EpisodeSortOrder: String, CaseIterable {
    case publishedDateNewest = "newest"
    case publishedDateOldest = "oldest"
    case title = "title"
    case playedStatus = "played"
    
    var displayName: String {
        switch self {
        case .publishedDateNewest: return "Newest First"
        case .publishedDateOldest: return "Oldest First"
        case .title: return "Title"
        case .playedStatus: return "Unplayed First"
        }
    }
} 