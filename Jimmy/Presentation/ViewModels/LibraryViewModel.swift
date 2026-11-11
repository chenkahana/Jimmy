import Foundation
import Combine
import SwiftUI
import GRDB
import os

struct LibraryState: Equatable {
    var isLoading = false
    var isStreamingEpisodes = false
    var streamingProgress = ""
    var errorMessage: String?
    var refreshID = UUID()
}

/// View model for Library with progressive loading and feature-scoped state.
@MainActor
class LibraryViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "LibraryViewModel")
    static let shared = LibraryViewModel()
    
    // MARK: - Published Properties
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false {
        didSet {
            state.isLoading = isLoading
        }
    }
    @Published var podcasts: [Podcast] = []
    @Published var isEditMode: Bool = false
    @Published var errorMessage: String? {
        didSet {
            state.errorMessage = errorMessage
        }
    }
    @Published var allEpisodes: [Episode] = []
    @Published var isStreamingEpisodes: Bool = false {
        didSet {
            state.isStreamingEpisodes = isStreamingEpisodes
        }
    }
    @Published var streamingProgress: String = "" {
        didSet {
            state.streamingProgress = streamingProgress
        }
    }
    @Published private(set) var state = LibraryState()
    @Published private(set) var refreshID = UUID()
    
    // MARK: - Progressive Sorting System
    private var progressiveSorter = ProgressivePodcastSorter()
    
    /// Change the sorting mode for podcasts
    func setSortMode(_ mode: ProgressivePodcastSorter.SortMode) {
        progressiveSorter.setSortMode(mode)
        // Trigger UI update
        objectWillChange.send()
    }
    
    /// Get current sort mode
    var currentSortMode: ProgressivePodcastSorter.SortMode {
        return progressiveSorter.currentSortMode
    }
    
    // MARK: - Shared Integration
    
    // Computed property for filtered podcasts with progressive sorting
    var filteredPodcasts: [Podcast] {
        let sortedPodcasts = progressiveSorter.getSortedPodcasts()
        
        if searchText.isEmpty {
            return sortedPodcasts
        } else {
            return sortedPodcasts.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.author.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    // MARK: - Dependencies
    private let subscriptionRepository: SubscriptionRepositoryProtocol
    private let episodeRepository: EpisodeRepositoryProtocol
    
    // Shared integration layer for coordinated background loading.
    private let libraryIntegration = WorldClassIntegration.shared
    
    private var cancellables = Set<AnyCancellable>()
    private var loadingTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var streamingTasks: [UUID: Task<Void, Never>] = [:]
    
    // MARK: - Initialization
    
    private init(
        subscriptionRepository: SubscriptionRepositoryProtocol = DIContainer.shared.subscriptionRepository,
        episodeRepository: EpisodeRepositoryProtocol = DIContainer.shared.episodeRepository
    ) {
        self.subscriptionRepository = subscriptionRepository
        self.episodeRepository = episodeRepository
        
        setupBindings()
        loadInitialData()
    }
    
    deinit {
        loadingTask?.cancel()
        refreshTask?.cancel()
        streamingTasks.values.forEach { $0.cancel() }
    }
    
    // MARK: - Data Loading
    
    private func setupBindings() {
        // Subscribe to progressive sorter updates to trigger UI refreshes
        progressiveSorter.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        let episodeStatusChanges = NotificationCenter.default.publisher(for: .episodeStatusUpdated).map { _ in () }
        Publishers.MergeMany(
            episodeStatusChanges.eraseToAnyPublisher(),
            QueueViewModel.shared.$episodes.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            let refreshID = UUID()
            self?.refreshID = refreshID
            self?.state.refreshID = refreshID
        }
        .store(in: &cancellables)
    }
    
    private func loadInitialData() {
        loadingTask = Task { @MainActor in
        await loadPodcastsFromDatabase()
        }
    }
    
    /// Load podcasts from database only - NO network calls
    /// This is used for fast library loading with progressive display
    func loadPodcastsFromDatabase() async {
        // Prevent multiple simultaneous loads
        guard !isLoading else { 
            return 
        }
        
        // ⚡ INSTANT LOADING: Check if we have cached sorted data for immediate display
        // Only return early if we actually have data IN MEMORY to show
        if progressiveSorter.hasCachedData() && !progressiveSorter.getSortedPodcasts().isEmpty {
            isLoading = false
            // UI will automatically show the cached sorted data via filteredPodcasts
            // But still refresh in background to ensure data is current
            Task.detached(priority: .background) { [weak self] in
                await self?.refreshInBackground()
            }
            return
        }
        isLoading = true
        errorMessage = nil
        
        // Clear existing podcasts for fresh progressive loading
        podcasts = []
        progressiveSorter.clear()
        
        // Safety mechanism: Force stop loading after timeout
        let timeoutSeconds: UInt64 = {
            #if targetEnvironment(simulator)
            return 5_000_000_000 // 5 seconds in simulator
            #else
            return 15_000_000_000 // 15 seconds on device
            #endif
        }()
        
                    Task {
                try? await Task.sleep(nanoseconds: timeoutSeconds)
                if isLoading {
                    await MainActor.run {
                        self.isLoading = false
                        self.errorMessage = nil
                    }
                }
            }
        
        // Start TRUE non-blocking streaming - NEVER blocks UI
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // Start background episode loading immediately
            Task.detached(priority: .background) { [weak self] in
                await self?.streamEpisodesFromCache()
            }
            
            // Stream podcasts with IMMEDIATE UI updates AND smart sorting
            await self.libraryIntegration.streamPodcastsNonBlocking(forceRefresh: false) { [weak self] podcast, count in
                // Each podcast appears INSTANTLY when ready in CORRECT SORT ORDER
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    
                    // Add to progressive sorter (maintains correct order)
                    self.progressiveSorter.addPodcast(podcast)
                    
                    // Also add to raw array for backward compatibility
                    if !self.podcasts.contains(where: { $0.id == podcast.id }) {
                        self.podcasts.append(podcast)
                    }
                    
                    // Turn off loading state after first podcast appears for instant UI responsiveness  
                    if count >= 1 && self.isLoading {
                        self.isLoading = false
                    }
                }
            }
            
            await MainActor.run { [weak self] in
                self?.isLoading = false
                
                // Update last successful load time for cache consistency
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "last_podcast_update")
            }
        }
    }
    
    /// Fallback method for when streaming fails
    private func loadPodcastsFallback() async {
        do {
            let subscriptions = try await subscriptionRepository.fetchSubscriptions(ignoreCache: false)
            let fallbackPodcasts = subscriptions.map { subscription in
                Podcast(
                    id: subscription.id,
                    title: subscription.title,
                    author: subscription.author,
                    description: subscription.description,
                    feedURL: subscription.feedURL,
                    artworkURL: subscription.artworkURL
                )
            }
            podcasts = fallbackPodcasts
            errorMessage = nil
        } catch {
            errorMessage = "Fallback loading failed: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
        
    /// Stream episodes from cache for all podcasts
    private func streamEpisodesFromCache() async {
        isStreamingEpisodes = true
        streamingProgress = "Loading episodes..."
        
        var allLoadedEpisodes: [Episode] = []
        let totalPodcasts = podcasts.count
        
        for (index, podcast) in podcasts.enumerated() {
            do {
                streamingProgress = "Loading episodes for \(podcast.title)... (\(index + 1)/\(totalPodcasts))"
                
                // Stream episodes incrementally so the episode list fills in progressively.
                let episodes = try await libraryIntegration.fetchEpisodes(for: podcast)
                allLoadedEpisodes.append(contentsOf: episodes)
                
                // Update progressive sorter with episode data for better sorting
                progressiveSorter.updateEpisodes(for: podcast.id, episodes: episodes)
                
                // Update UI incrementally with SORTED episodes
                // Enforce global sort order to ensure "Recent Episodes" is always correct
                let sortedEpisodes = allLoadedEpisodes.sorted {
                    ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast)
                }
                allEpisodes = sortedEpisodes
                
            } catch {
                Log.data.error("LibraryViewModel-StreamEpisodes failed for \(podcast.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }
        }
        
        isStreamingEpisodes = false
        streamingProgress = ""
    }
    
    /// Stream episodes for a specific podcast
    func streamEpisodesForPodcast(_ podcast: Podcast) async {
        // Cancel existing task for this podcast
        streamingTasks[podcast.id]?.cancel()
        
        streamingTasks[podcast.id] = Task {
            do {
                // Refresh a single show's episodes without rebuilding the whole library.
                let episodes = try await libraryIntegration.fetchEpisodes(for: podcast)
                
                await MainActor.run {
                    var currentEpisodes = allEpisodes
                    
                    // Remove old episodes for this podcast
                    currentEpisodes.removeAll { $0.podcastID == podcast.id }
                    
                    // Add new episodes
                    currentEpisodes.append(contentsOf: episodes)
                    
                    // Enforce global sort order
                    allEpisodes = currentEpisodes.sorted {
                        ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast)
                    }
                }
            
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load episodes for \(podcast.title): \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// Refresh data manually (user-initiated)
    func refreshData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Refresh shows from the network while preserving the current episode list.
            let sortedPodcasts = try await libraryIntegration.fetchPodcasts(forceRefresh: true)
            podcasts = sortedPodcasts
            
            // DON'T clear existing episodes - preserve them and update incrementally
            // This prevents the sorting mechanism from being reset
            
            // Stream any new episodes without clearing existing ones
            await streamEpisodesFromCache()
            
        } catch {
            errorMessage = "Failed to refresh data: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Episode Management
    
    /// Get recent episodes across all podcasts (for Episodes tab)
    func getRecentEpisodes(limit: Int = 100) -> [Episode] {
        // Since allEpisodes is now guaranteed to be sorted by date,
        // we can just take the prefix for instant performance
        return Array(allEpisodes.prefix(limit))
    }
    
    /// Get episodes for a specific podcast
    func getEpisodes(for podcast: Podcast) -> [Episode] {
        // Even for single podcast, we filter the sorted list
        // which implicitly maintains date order
        return allEpisodes
            .filter { $0.podcastID == podcast.id }
    }
    
    /// Check if episodes are loaded for a podcast
    func hasEpisodes(for podcast: Podcast) -> Bool {
        return allEpisodes.contains { $0.podcastID == podcast.id }
    }
    
    /// Get episode count for a podcast
    func getEpisodeCount(for podcast: Podcast) -> Int {
        return allEpisodes.filter { $0.podcastID == podcast.id }.count
    }
    
    // MARK: - Sorting Helpers
    
    /// Get podcasts sorted by newest episode date.
    func getSortedPodcasts() -> [Podcast] {
        // Return the current snapshot immediately, then reconcile with fresher sort data.
        let currentPodcasts = filteredPodcasts
        
        Task {
            let sortedPodcasts = await libraryIntegration.getSortedPodcasts()
            await MainActor.run {
                self.podcasts = sortedPodcasts
            }
        }
        
        return currentPodcasts
    }
    
    /// Deprecated compatibility shim for older callers.
    @available(*, deprecated, message: "Use WorldClassIntegration.getSortedPodcasts() instead")
    func getCachedSortedPodcasts() -> [Podcast] {
        return filteredPodcasts
    }
    
    // MARK: - Podcast Management
    
    /// Remove a podcast (for compatibility)
    func removePodcast(_ podcast: Podcast) async {
        // Keep the UI snapshot in sync immediately.
        podcasts.removeAll { $0.id == podcast.id }
        allEpisodes.removeAll { $0.podcastID == podcast.id }
    }
    
    /// Toggle edit mode
    func toggleEditMode() {
        isEditMode.toggle()
    }
    
    /// Reset database (for debugging)
    func resetDatabase() async {
        do {
            // Remove all subscriptions from the database
            try await subscriptionRepository.removeAllSubscriptions()
            
            // Clear local state
            podcasts.removeAll()
            allEpisodes.removeAll()
            
            // Clear progressive sorter
            progressiveSorter.clear()
            
            // Refresh subscription state manager
            await SubscriptionStateManager.shared.refreshSubscriptionStates()
            
            Self.logger.info("LibraryViewModel: Successfully deleted all podcasts from database")
            
        } catch {
            errorMessage = "Failed to delete all podcasts: \(error.localizedDescription)"
            Self.logger.error("LibraryViewModel: Failed to delete all podcasts: \(error)")
        }
    }
    
    /// Force resort (for debugging)
    func forceResort() {
        // Explicitly resort allEpisodes to ensure correct order
        // This is useful if the sort order somehow became corrupted
        allEpisodes.sort {
            ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast)
        }
        objectWillChange.send()
    }
    
    /// Debug legacy data sources (for debugging)
    func debugLegacyDataSources() {
        // No legacy data sources to debug
    }
    
    /// Force migration completed (for debugging)
    func forceMigrationCompleted() {
        // Migration is already complete in the current library pipeline.
    }
    
    /// Load data if needed
    func loadDataIfNeeded() async {
        if podcasts.isEmpty {
            await loadPodcastsFromDatabase()
            
            // Safety check: ensure loading state is cleared
            await MainActor.run {
                if self.isLoading {
                    self.isLoading = false
                }
            }
        }
    }
    
    /// Background refresh without affecting UI loading state
    private func refreshInBackground() async {
        // Check if data actually needs refreshing (avoid unnecessary work)
        let lastUpdateTime = UserDefaults.standard.double(forKey: "last_podcast_update")
        let currentTime = Date().timeIntervalSince1970
        let timeSinceUpdate = currentTime - lastUpdateTime
        
        // If data was updated less than 5 minutes ago, skip background refresh
        if timeSinceUpdate < 300 { // 5 minutes
            return
        }
        
        // Silently refresh data in background without showing loading state
        await libraryIntegration.streamPodcastsNonBlocking(forceRefresh: true) { [weak self] podcast, count in
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                
                // Update progressive sorter (this maintains consistency)
                self.progressiveSorter.addPodcast(podcast)
                
                // Also add to raw array for backward compatibility
                if !self.podcasts.contains(where: { $0.id == podcast.id }) {
                    self.podcasts.append(podcast)
                }
            }
        }
        
        // Update last refresh time
        UserDefaults.standard.set(currentTime, forKey: "last_podcast_update")
    }
    
    /// Force refresh with progressive loading - shows appear one by one
    func refreshWithProgressiveLoading() async {
        // Clear existing data for fresh progressive load
        podcasts = []
        allEpisodes = []
        progressiveSorter.clear()
        
        // Start non-blocking progressive refresh - NEVER blocks UI
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // Stream refreshed podcasts with immediate UI updates AND smart sorting
            await self.libraryIntegration.streamPodcastsNonBlocking(forceRefresh: true) { [weak self] podcast, count in
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    
                    // Add to progressive sorter (maintains correct order during refresh)
                    self.progressiveSorter.addPodcast(podcast)
                    
                    // Also add to raw array for backward compatibility
                    if !self.podcasts.contains(where: { $0.id == podcast.id }) {
                        self.podcasts.append(podcast)
                    }
                    
                    // Clear loading state immediately for responsive feel
                    if count >= 1 && self.isLoading {
                        self.isLoading = false
                    }
                }
            }
            
            await MainActor.run { [weak self] in
                // Update last successful refresh time for cache consistency
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "last_podcast_update")
            }
        }
    }
    
    // MARK: - Utility Functions
    
    /// Add timeout to async operations to prevent endless loading
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            
            group.cancelAll()
            return result
        }
    }
    
    // Older sorting and caching helpers were retired in favor of the progressive loader above.
}
