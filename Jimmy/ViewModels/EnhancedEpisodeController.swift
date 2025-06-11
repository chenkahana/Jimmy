import Foundation
import SwiftUI
import Combine
#if canImport(OSLog)
import OSLog
#endif

/// Enhanced episode controller that provides non-blocking UI interface
/// Shows cached data immediately and coordinates with background worker
@MainActor
class EnhancedEpisodeController: ObservableObject {
    static let shared = EnhancedEpisodeController()
    
    // MARK: - Published Properties
    
    @Published private(set) var episodes: [Episode] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdateTime: Date?
    @Published private(set) var cacheStatus: CacheStatus = .unknown
    
    // MARK: - Cache Status
    
    enum CacheStatus {
        case unknown
        case fresh
        case stale
        case empty
        case error
        
        var displayText: String {
            switch self {
            case .unknown: return "Checking cache..."
            case .fresh: return "Up to date"
            case .stale: return "Updating..."
            case .empty: return "Loading episodes..."
            case .error: return "Error loading"
            }
        }
        
        var needsRefresh: Bool {
            switch self {
            case .stale, .empty, .error: return true
            case .fresh, .unknown: return false
            }
        }
    }
    
    // MARK: - Private Properties
    
    private let repository = EpisodeRepository.shared
    private let fetchWorker = EpisodeFetchWorker.shared
    private var cancellables = Set<AnyCancellable>()
    
    /// Debouncing for user-initiated refreshes
    private var refreshWorkItem: DispatchWorkItem?
    private let refreshDebounceInterval: TimeInterval = 1.0
    
    /// Track user interactions
    private var userInitiatedRefresh: Bool = false
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "com.jimmy.app", category: "episode-controller")
    #endif
    
    // MARK: - Initialization
    
    private init() {
        setupRepositoryObservation()
        setupNotificationObservers()
        loadInitialData()
    }
    
    // MARK: - Public Interface
    
    /// Load episodes for display (non-blocking, shows cache immediately)
    func loadEpisodes() async {
        #if canImport(OSLog)
        logger.info("📱 Loading episodes for display")
        #endif
        
        // 1. Show cached data immediately
        await displayCachedData()
        
        // 2. Check if refresh is needed
        let needsRefresh = await repository.needsRefresh()
        
        if needsRefresh {
            await updateCacheStatus(.stale)
            
            // 3. Queue background refresh (non-blocking)
            let request = FetchEpisodesRequest.backgroundRefresh()
            await fetchWorker.enqueue(request)
        } else {
            await updateCacheStatus(.fresh)
        }
    }
    
    /// User-initiated refresh (higher priority)
    func refreshEpisodes() async {
        guard !userInitiatedRefresh else { return }
        
        userInitiatedRefresh = true
        defer { userInitiatedRefresh = false }
        
        #if canImport(OSLog)
        logger.info("🔄 User-initiated episode refresh")
        #endif
        
        await updateCacheStatus(.stale)
        await setRefreshing(true)
        
        // Cancel any pending refresh
        refreshWorkItem?.cancel()
        
        // Create debounced refresh
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                await self?.performUserRefresh()
            }
        }
        refreshWorkItem = workItem
        
        DispatchQueue.main.asyncAfter(deadline: .now() + refreshDebounceInterval, execute: workItem)
    }
    
    /// Load episodes for a specific podcast
    func loadEpisodes(for podcastID: UUID) async {
        #if canImport(OSLog)
        logger.info("📱 Loading episodes for podcast: \(podcastID)")
        #endif
        
        // Show existing episodes for this podcast immediately
        await displayEpisodesForPodcast(podcastID)
        
        // Queue fetch for this specific podcast
        let request = FetchEpisodesRequest.singlePodcast(podcastID, priority: .high)
        await fetchWorker.enqueue(request)
    }
    
    /// Mark episode as played/unplayed
    func markEpisodeAsPlayed(_ episode: Episode, played: Bool) async {
        // Update local state immediately for responsive UI
        if let index = episodes.firstIndex(where: { $0.id == episode.id }) {
            episodes[index].played = played
        }
        
        // Update repository
        if played {
            await repository.markEpisodeAsPlayed(episode.id)
        }
        
        #if canImport(OSLog)
        logger.info("✅ Marked episode as \(played ? "played" : "unplayed"): \(episode.title)")
        #endif
    }
    
    /// Get episodes for a specific podcast
    func getEpisodes(for podcastID: UUID) -> [Episode] {
        return episodes.filter { $0.podcastID == podcastID }
    }
    
    /// Get total episode count
    var episodeCount: Int {
        return episodes.count
    }
    
    /// Check if episodes are available
    var hasEpisodes: Bool {
        return !episodes.isEmpty
    }
    
    /// Force immediate processing of queued requests
    func processQueuedRequests() async {
        await fetchWorker.processImmediately()
    }
    
    /// Clear all episodes and refresh
    func clearAndRefresh() async {
        await repository.clearAllEpisodes()
        await refreshEpisodes()
    }
    
    // MARK: - Private Methods
    
    private func setupRepositoryObservation() {
        // Observe repository changes
        repository.$episodes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newEpisodes in
                self?.episodes = newEpisodes
                self?.updateCacheStatusBasedOnData()
            }
            .store(in: &cancellables)
        
        repository.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                self?.isLoading = loading
            }
            .store(in: &cancellables)
        
        repository.$lastUpdateTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updateTime in
                self?.lastUpdateTime = updateTime
            }
            .store(in: &cancellables)
        
        repository.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorMessage = error
                if error != nil {
                    Task { @MainActor in
                        await self?.updateCacheStatus(.error)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .episodeRepositoryUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleRepositoryUpdate()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .episodeRepositoryError,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                await self?.handleRepositoryError(notification)
            }
        }
    }
    
    private func loadInitialData() {
        Task {
            await displayCachedData()
            
            // Check if we need to load fresh data
            let stats = await repository.getCacheStats()
            
            if stats.count == 0 {
                await updateCacheStatus(.empty)
                
                // Queue initial load
                let request = FetchEpisodesRequest.userInitiatedRefresh()
                await fetchWorker.enqueue(request)
            } else if stats.needsRefresh {
                await updateCacheStatus(.stale)
                
                // Queue background refresh
                let request = FetchEpisodesRequest.backgroundRefresh()
                await fetchWorker.enqueue(request)
            } else {
                await updateCacheStatus(.fresh)
            }
        }
    }
    
    private func displayCachedData() async {
        let cachedEpisodes = await repository.getAllEpisodes()
        episodes = cachedEpisodes
        
        #if canImport(OSLog)
        logger.info("📱 Displayed \(cachedEpisodes.count) cached episodes")
        #endif
    }
    
    private func displayEpisodesForPodcast(_ podcastID: UUID) async {
        let podcastEpisodes = await repository.getEpisodes(for: podcastID)
        
        // Update episodes to show only this podcast's episodes
        episodes = podcastEpisodes
        
        #if canImport(OSLog)
        logger.info("📱 Displayed \(podcastEpisodes.count) episodes for podcast")
        #endif
    }
    
    private func performUserRefresh() async {
        defer {
            Task { @MainActor in
                await self.setRefreshing(false)
            }
        }
        
        // Clear any existing errors
        errorMessage = nil
        
        // Queue high-priority refresh
        let request = FetchEpisodesRequest.userInitiatedRefresh()
        await fetchWorker.enqueue(request)
        
        // Process immediately for user-initiated requests
        await fetchWorker.processImmediately()
    }
    
    private func updateCacheStatus(_ status: CacheStatus) async {
        cacheStatus = status
        
        #if canImport(OSLog)
        logger.info("📊 Cache status updated: \(status.displayText)")
        #endif
    }
    
    private func updateCacheStatusBasedOnData() {
        Task { @MainActor in
            if episodes.isEmpty {
                await updateCacheStatus(.empty)
            } else {
                let stats = await repository.getCacheStats()
                if stats.needsRefresh {
                    await updateCacheStatus(.stale)
                } else {
                    await updateCacheStatus(.fresh)
                }
            }
        }
    }
    
    private func setRefreshing(_ refreshing: Bool) async {
        isRefreshing = refreshing
    }
    
    private func handleRepositoryUpdate() async {
        #if canImport(OSLog)
        logger.info("📥 Repository updated, refreshing display")
        #endif
        
        await displayCachedData()
        await updateCacheStatus(.fresh)
        await setRefreshing(false)
    }
    
    private func handleRepositoryError(_ notification: Notification) async {
        if let error = notification.object as? String {
            errorMessage = error
        } else {
            errorMessage = "Unknown error occurred"
        }
        
        await updateCacheStatus(.error)
        await setRefreshing(false)
        
        #if canImport(OSLog)
        logger.error("❌ Repository error: \(self.errorMessage ?? "unknown")")
        #endif
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Convenience Methods

extension EnhancedEpisodeController {
    /// Get episodes grouped by podcast
    func getEpisodesGroupedByPodcast() -> [UUID: [Episode]] {
        return Dictionary(grouping: episodes) { episode in
            episode.podcastID ?? UUID() // Provide default UUID for episodes without podcastID
        }
    }
    
    /// Get recent episodes (last 7 days)
    func getRecentEpisodes() -> [Episode] {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return episodes.filter { episode in
            guard let publishedDate = episode.publishedDate else { return false }
            return publishedDate >= sevenDaysAgo
        }
    }
    
    /// Get unplayed episodes
    func getUnplayedEpisodes() -> [Episode] {
        return episodes.filter { !$0.played }
    }
    
    /// Get played episodes
    func getPlayedEpisodes() -> [Episode] {
        return episodes.filter { $0.played }
    }
    
    /// Search episodes by title or description
    func searchEpisodes(_ query: String) -> [Episode] {
        guard !query.isEmpty else { return episodes }
        
        let lowercaseQuery = query.lowercased()
        return episodes.filter { episode in
            let titleMatch = episode.title.lowercased().contains(lowercaseQuery)
            let descriptionMatch = episode.description?.lowercased().contains(lowercaseQuery) ?? false
            return titleMatch || descriptionMatch
        }
    }
}

// MARK: - Debug Helpers

#if DEBUG
extension EnhancedEpisodeController {
    /// Get debug information about the controller state
    func getDebugInfo() -> String {
        let lastUpdateText = lastUpdateTime?.formatted() ?? "Never"
        let errorText = errorMessage ?? "None"
        
        return """
        Enhanced Episode Controller Debug Info:
        - Episodes: \(episodes.count)
        - Loading: \(isLoading)
        - Refreshing: \(isRefreshing)
        - Cache Status: \(cacheStatus.displayText)
        - Last Update: \(lastUpdateText)
        - Error: \(errorText)
        """
    }
    
    /// Force a specific cache status for testing
    func setDebugCacheStatus(_ status: CacheStatus) async {
        await updateCacheStatus(status)
    }
}
#endif 