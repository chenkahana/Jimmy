import Foundation
import SwiftUI
import OSLog
import Combine

/// Library Controller for managing podcast library UI state and operations
/// Handles filtering, sorting, search, and edit mode for the Library view
@MainActor
final class LibraryController: ObservableObject {
    static let shared = LibraryController()
    
    // MARK: - Published Properties
    
    @Published var searchText: String = ""
    @Published var selectedViewType: LibraryViewType = .grid
    @Published var isEditMode: Bool = false
    @Published var sortOrder: PodcastSortOrder = .lastEpisodeDate
    @Published var episodeSortOrder: EpisodeSortOrder = .publishedDateNewest
    
    @Published private(set) var filteredPodcasts: [Podcast] = []
    @Published private(set) var filteredEpisodes: [Episode] = []
    @Published private(set) var subscribedPodcasts: [Podcast] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    
    @Published private var isRepairing: Bool = false
    
    // MARK: - View Types
    
    enum LibraryViewType: String, CaseIterable {
        case shows = "Shows"
        case grid = "Grid"
        case episodes = "Episodes"
        
        var displayName: String { rawValue }
    }
    
    // MARK: - Sort Orders
    
    enum PodcastSortOrder: String, CaseIterable {
        case lastEpisodeDate = "lastEpisodeDate"
        case title = "title"
        case author = "author"
        case subscriptionDate = "subscriptionDate"
        
        var displayName: String {
            switch self {
            case .lastEpisodeDate: return "Latest Episode"
            case .title: return "Title"
            case .author: return "Author"
            case .subscriptionDate: return "Recently Added"
            }
        }
    }
    

    
    // MARK: - Private Properties
    
    private let episodeController = UnifiedEpisodeController.shared
    private let podcastService = PodcastService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Cache for performance
    private var lastSearchText: String = ""
    private var lastPodcastsHash: Int = 0
    private var lastEpisodesHash: Int = 0
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "Jimmy", category: "LibraryController")
    #endif
    
    // MARK: - Initialization
    
    private init() {
        setupObservers()
        
        // Add notification observer for iCloud data loading
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleiCloudDataLoaded),
            name: NSNotification.Name("iCloudDataLoaded"),
            object: nil
        )
        
        Task {
            await loadPodcasts()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleiCloudDataLoaded() {
        #if canImport(OSLog)
        logger.info("📱 LibraryController: Received iCloud data loaded notification - reloading podcasts")
        #endif
        
        Task {
            await loadPodcasts()
        }
    }
    
    // MARK: - Public Interface
    
    /// Load podcasts and episodes
    func loadData() {
        guard !isLoading else { return } // Prevent multiple simultaneous loads
        
        isLoading = true
        errorMessage = nil
        
        Task {
            // Add timeout protection
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds timeout
                await MainActor.run { [weak self] in
                    if self?.isLoading == true {
                        self?.isLoading = false
                        self?.errorMessage = "Loading timed out. Please try again."
                    }
                }
            }
            
            // Load podcasts immediately
            await loadPodcasts()
            await updateFilteredContent()
            
            // Cancel timeout and set loading to false
            timeoutTask.cancel()
            await MainActor.run { [weak self] in
                self?.isLoading = false
            }
            
            // Load episodes in background without blocking UI (fire and forget)
            Task.detached(priority: .background) { [weak self] in
                await self?.loadEpisodesInBackground()
            }
        }
    }
    
    /// Refresh all data
    func refreshData() {
        #if canImport(OSLog)
        logger.info("🔄 Refreshing library data")
        #endif
        
        // Refresh episodes through episode controller
        episodeController.forceRefresh()
        
        // Refresh podcast artwork
        refreshPodcastArtwork()
        
        // Reload podcasts
        loadData()
    }
    
    /// Refresh artwork for all podcasts
    private func refreshPodcastArtwork() {
        Task {
            #if canImport(OSLog)
            logger.info("🎨 Refreshing podcast artwork")
            #endif
            
            await withCheckedContinuation { continuation in
                podcastService.refreshAllPodcastArtwork { processed, total in
                    #if canImport(OSLog)
                    self.logger.info("🎨 Artwork refresh complete: \(processed)/\(total) podcasts")
                    #endif
                    continuation.resume()
                }
            }
        }
    }
    
    /// Delete podcast
    func deletePodcast(_ podcast: Podcast) {
        #if canImport(OSLog)
        logger.info("🗑️ Deleting podcast: \(podcast.title)")
        #endif
        
        // Record for undo
        ShakeUndoManager.shared.recordOperation(
            .subscriptionRemoved(podcast: podcast),
            description: "Unsubscribed from \"\(podcast.title)\""
        )
        
        // Remove from local array
        subscribedPodcasts.removeAll { $0.id == podcast.id }
        
        // Save to disk
        podcastService.savePodcasts(subscribedPodcasts)
        
        // Update filtered content
        Task {
            await updateFilteredContent()
        }
        
        // Remove episodes from queue if any
        let queueViewModel = QueueViewModel.shared
        let episodesToRemove = queueViewModel.queue.filter { $0.podcastID == podcast.id }
        if !episodesToRemove.isEmpty {
            let idsToRemove = Set(episodesToRemove.map { $0.id })
            queueViewModel.removeEpisodes(withIDs: idsToRemove)
        }
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    /// Toggle edit mode
    func toggleEditMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditMode.toggle()
        }
    }
    
    /// Clear search
    func clearSearch() {
        searchText = ""
    }
    
    /// Get podcast for episode
    func getPodcast(for episode: Episode) -> Podcast? {
        guard let podcastID = episode.podcastID else { return nil }
        return subscribedPodcasts.first { $0.id == podcastID }
    }
    
    /// Get episodes count for podcast
    func getEpisodesCount(for podcast: Podcast) -> Int {
        let count = episodeController.getEpisodes(for: podcast.id).count
        #if canImport(OSLog)
        if count == 0 {
            logger.info("⚠️ No episodes found for podcast: \(podcast.title) (ID: \(podcast.id))")
            logger.info("📊 Total episodes in controller: \(self.episodeController.getEpisodeCount())")
        }
        #endif
        return count
    }
    
    /// Get unplayed episodes count for podcast
    func getUnplayedEpisodesCount(for podcast: Podcast) -> Int {
        return episodeController.getUnplayedEpisodes(for: podcast.id).count
    }
    
    /// Check if podcast has new episodes
    func hasNewEpisodes(_ podcast: Podcast) -> Bool {
        let unplayedCount = getUnplayedEpisodesCount(for: podcast)
        return unplayedCount > 0
    }
    
    /// Public method to trigger data reload (e.g., after iCloud sync)
    func reloadData() {
        Task {
            await loadPodcasts()
        }
    }
    
    // MARK: - Private Methods
    
    /// Setup observers for data changes
    private func setupObservers() {
        // Observe search text changes
        $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.updateFilteredContent()
                }
            }
            .store(in: &cancellables)
        
        // Observe sort order changes
        $sortOrder
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.updateFilteredContent()
                }
            }
            .store(in: &cancellables)
        
        // Observe episode sort order changes
        $episodeSortOrder
            .removeDuplicates()
            .sink { [weak self] (sortOrder: EpisodeSortOrder) in
                Task { [weak self] in
                    await self?.updateFilteredContent()
                }
            }
            .store(in: &cancellables)
        
        // Observe view type changes
        $selectedViewType
            .removeDuplicates()
            .sink { [weak self] _ in
                // Reset edit mode when switching views
                self?.isEditMode = false
                
                Task { [weak self] in
                    await self?.updateFilteredContent()
                }
            }
            .store(in: &cancellables)
        
        // Observe episode controller changes
        episodeController.$episodes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.updateFilteredContent()
                }
            }
            .store(in: &cancellables)
    }
    
    /// Load podcasts from service
    private func loadPodcasts() async {
        #if canImport(OSLog)
        logger.info("🔍 LibraryController: Starting loadPodcasts()")
        #endif
        
        let podcasts = await podcastService.loadPodcastsAsync()
        
        #if canImport(OSLog)
        logger.info("📦 LibraryController: Loaded \(podcasts.count) podcasts from service")
        
        // Debug: Check if PodcastService has attempted load
        logger.info("📦 PodcastService hasAttemptedLoad: \(self.podcastService.hasAttemptedLoad)")
        
        // Debug: Try synchronous load to compare
        let syncPodcasts = self.podcastService.loadPodcasts()
        logger.info("📦 Synchronous load returned: \(syncPodcasts.count) podcasts")
        
        // Debug: Check UserDefaults directly
        if let data = UserDefaults.standard.data(forKey: "podcastsKey") {
            logger.info("📦 UserDefaults has podcast data: \(data.count) bytes")
            if let directPodcasts = try? JSONDecoder().decode([Podcast].self, from: data) {
                logger.info("📦 Direct UserDefaults decode: \(directPodcasts.count) podcasts")
                if directPodcasts.count > 0 {
                    logger.info("📦 First podcast from UserDefaults: \(directPodcasts[0].title)")
                }
            } else {
                logger.info("📦 Failed to decode podcast data from UserDefaults")
            }
        } else {
            logger.info("📦 No podcast data found in UserDefaults")
        }
        #endif
        
        // Check for podcast-episode ID mismatches and attempt to repair
        await repairPodcastEpisodeIDMismatches(podcasts: podcasts)
        
        await MainActor.run { [weak self] in
            self?.subscribedPodcasts = podcasts
            #if canImport(OSLog)
            self?.logger.info("📦 LibraryController: Updated subscribedPodcasts to \(podcasts.count) items")
            if podcasts.count > 0 {
                self?.logger.info("📦 First few podcasts: \(podcasts.prefix(3).map(\.title))")
                self?.logger.info("📦 First few podcast IDs: \(podcasts.prefix(3).map(\.id))")
                
                // Debug episode controller state
                if let strongSelf = self {
                    let totalEpisodes = strongSelf.episodeController.getEpisodeCount()
                    strongSelf.logger.info("📊 Episode controller has \(totalEpisodes) total episodes")
                    
                    if totalEpisodes > 0 {
                        let allEpisodes = strongSelf.episodeController.getAllEpisodes()
                        let uniquePodcastIDs = Set(allEpisodes.compactMap(\.podcastID))
                        strongSelf.logger.info("📊 Episodes belong to \(uniquePodcastIDs.count) unique podcast IDs")
                        strongSelf.logger.info("📊 First few episode podcast IDs: \(Array(uniquePodcastIDs.prefix(3)))")
                    }
                }
            }
            #endif
        }
    }
    
    /// Repair podcast-episode ID mismatches by matching podcasts to episodes by feed URL
    private func repairPodcastEpisodeIDMismatches(podcasts: [Podcast]) async {
        let allEpisodes = episodeController.getAllEpisodes()
        let episodePodcastIDs = Set(allEpisodes.compactMap(\.podcastID))
        let podcastIDs = Set(podcasts.map(\.id))
        
        // Check if all podcast IDs from the library are present among the episodes' podcast IDs.
        // If not, it indicates a mismatch that needs repair.
        let isMismatch = !podcastIDs.isSubset(of: episodePodcastIDs)
        
        #if canImport(OSLog)
        logger.info("🔧 Checking ID mismatch - Library Podcast IDs: \(podcastIDs.count), Episode Podcast IDs: \(episodePodcastIDs.count), Matches: \(episodePodcastIDs.intersection(podcastIDs).count)")
        #endif
        
        if isMismatch && !podcasts.isEmpty && !allEpisodes.isEmpty {
            #if canImport(OSLog)
            logger.info("🔧 Detected podcast-episode ID mismatch, triggering episode refresh and bypassing filter.")
            #endif
            
            await MainActor.run {
                self.isRepairing = true
            }
            
            // Force refresh episodes for all podcasts to fix ID mismatches
            Task {
                await MainActor.run { [weak self] in
                    self?.episodeController.forceRefresh()
                }
                
                // After a longer delay to allow background refresh, disable repair mode and update content
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                
                await MainActor.run { [weak self] in
                    self?.isRepairing = false
                    #if canImport(OSLog)
                    self?.logger.info("✅ Repair period finished. Restoring normal filtering.")
                    #endif
                }
                await self.updateFilteredContent()
            }
        }
    }
    
    /// Load episodes for all podcasts to ensure data is available
    private func loadEpisodesForAllPodcasts(_ podcasts: [Podcast]) async {
        guard !podcasts.isEmpty else { 
            #if canImport(OSLog)
            logger.info("📦 No podcasts to load episodes for")
            #endif
            return 
        }
        
        #if canImport(OSLog)
        logger.info("🔄 Loading episodes for \(podcasts.count) podcasts in background")
        #endif
        
        // Use OptimizedPodcastService to batch fetch episodes with timeout
        await withCheckedContinuation { continuation in
            var isCompleted = false
            
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds timeout
                if !isCompleted {
                    isCompleted = true
                    #if canImport(OSLog)
                    self.logger.info("⏰ Background episode loading timed out after 10 seconds")
                    #endif
                    continuation.resume()
                }
            }
            
            OptimizedPodcastService.shared.batchFetchEpisodes(for: podcasts) { results in
                timeoutTask.cancel()
                if !isCompleted {
                    isCompleted = true
                    #if canImport(OSLog)
                    self.logger.info("✅ Background episode loading completed for \(results.count) podcasts")
                    #endif
                    continuation.resume()
                }
            }
        }
    }
    
    /// Update filtered content based on current filters
    private func updateFilteredContent() async {
        let currentSearchText = await MainActor.run { searchText }
        let currentSortOrder = await MainActor.run { sortOrder }
        let currentEpisodeSortOrder = await MainActor.run { episodeSortOrder }
        let currentPodcasts = await MainActor.run { subscribedPodcasts }
        let currentViewType = await MainActor.run { selectedViewType }
        
        #if canImport(OSLog)
        logger.info("🔄 updateFilteredContent called with \(currentPodcasts.count) podcasts")
        #endif
        
        // Guard against empty podcasts during initialization
        guard !currentPodcasts.isEmpty else {
            #if canImport(OSLog)
            logger.info("⚠️ Skipping updateFilteredContent - no podcasts available yet")
            #endif
            return
        }
        
        // Check if we need to update (performance optimization)
        let podcastsHash = currentPodcasts.map(\.id).hashValue
        let episodesHash = episodeController.getAllEpisodes().map(\.id).hashValue
        
        let needsUpdate = currentSearchText != lastSearchText ||
                         podcastsHash != lastPodcastsHash ||
                         episodesHash != lastEpisodesHash
        
        guard needsUpdate else { return }
        
        // Skip filtering if repairing to prevent empty view
        if isRepairing {
            self.filteredPodcasts = currentPodcasts
            #if canImport(OSLog)
            logger.info("⚠️ Repair in progress, temporarily showing all podcasts to avoid empty screen.")
            #endif
            return
        }
        
        // Update podcasts
        let filteredPodcasts = await filterAndSortPodcasts(
            podcasts: currentPodcasts,
            searchText: currentSearchText,
            sortOrder: currentSortOrder
        )
        
        // Update episodes if needed
        let filteredEpisodes = currentViewType == .episodes ? 
            await filterAndSortEpisodes(
                searchText: currentSearchText,
                sortOrder: currentEpisodeSortOrder
            ) : []
        
                    await MainActor.run { [weak self] in
            self?.filteredPodcasts = filteredPodcasts
            self?.filteredEpisodes = filteredEpisodes
            
            #if canImport(OSLog)
            self?.logger.info("📱 LibraryController: Updated filtered content - Podcasts: \(filteredPodcasts.count), Episodes: \(filteredEpisodes.count)")
            #endif
            
            // Update cache values
            self?.lastSearchText = currentSearchText
            self?.lastPodcastsHash = podcastsHash
            self?.lastEpisodesHash = episodesHash
        }
    }
    
    /// Filter and sort podcasts
    private func filterAndSortPodcasts(
        podcasts: [Podcast],
        searchText: String,
        sortOrder: PodcastSortOrder
    ) async -> [Podcast] {
        
        #if canImport(OSLog)
        logger.info("🔍 Filtering \(podcasts.count) podcasts with search: '\(searchText)', sort: \(String(describing: sortOrder))")
        #endif
        
        // Filter by search text
        let filtered = searchText.isEmpty ? podcasts : podcasts.filter { podcast in
            podcast.title.localizedCaseInsensitiveContains(searchText) ||
            podcast.author.localizedCaseInsensitiveContains(searchText) ||
            podcast.description.localizedCaseInsensitiveContains(searchText)
        }
        
        #if canImport(OSLog)
        logger.info("🔍 After text filtering: \(filtered.count) podcasts")
        #endif
        
        // Sort podcasts
        let sorted = filtered.sorted { podcast1, podcast2 in
            switch sortOrder {
            case .lastEpisodeDate:
                // Sort by last episode date (most recent first)
                switch (podcast1.lastEpisodeDate, podcast2.lastEpisodeDate) {
                case (let date1?, let date2?):
                    return date1 > date2
                case (nil, _?):
                    return false // Podcasts without dates go to the end
                case (_?, nil):
                    return true // Podcasts with dates come before those without
                case (nil, nil):
                    return podcast1.title.localizedCaseInsensitiveCompare(podcast2.title) == .orderedAscending
                }
                
            case .title:
                return podcast1.title.localizedCaseInsensitiveCompare(podcast2.title) == .orderedAscending
                
            case .author:
                return podcast1.author.localizedCaseInsensitiveCompare(podcast2.author) == .orderedAscending
                
            case .subscriptionDate:
                // For now, use title as fallback since we don't track subscription date
                return podcast1.title.localizedCaseInsensitiveCompare(podcast2.title) == .orderedAscending
            }
        }
        
        #if canImport(OSLog)
        logger.info("🔍 After sorting: \(sorted.count) podcasts")
        #endif
        
        return sorted
    }
    
    /// Filter and sort episodes
    private func filterAndSortEpisodes(
        searchText: String,
        sortOrder: EpisodeSortOrder
    ) async -> [Episode] {
        
        let allEpisodes = episodeController.getAllEpisodes()
        let subscribedPodcastIDs = Set(subscribedPodcasts.map(\.id))
        
        // Filter episodes for subscribed podcasts
        let subscribedEpisodes = allEpisodes.filter { episode in
            guard let podcastID = episode.podcastID else { return false }
            return subscribedPodcastIDs.contains(podcastID)
        }
        
        // Filter by search text
        let filtered = searchText.isEmpty ? subscribedEpisodes : subscribedEpisodes.filter { episode in
            episode.title.localizedCaseInsensitiveContains(searchText) ||
            episode.description?.localizedCaseInsensitiveContains(searchText) == true
        }
        
        // Sort episodes using episode controller's sorting
        return episodeController.getEpisodes(for: UUID(), sortedBy: sortOrder)
            .filter { episode in
                filtered.contains { $0.id == episode.id }
            }
    }
    
    /// Load episodes in background without blocking UI
    private func loadEpisodesInBackground() async {
        // Load episodes in background without blocking UI
        await loadEpisodesForAllPodcasts(subscribedPodcasts)
    }
}

// MARK: - Convenience Methods

extension LibraryController {
    /// Get display text for current state
    var statusText: String {
        if isLoading {
            return "Loading..."
        }
        
        switch selectedViewType {
        case .shows, .grid:
            if filteredPodcasts.isEmpty {
                return searchText.isEmpty ? "No subscriptions" : "No results"
            } else {
                return "\(filteredPodcasts.count) show\(filteredPodcasts.count == 1 ? "" : "s")"
            }
            
        case .episodes:
            if filteredEpisodes.isEmpty {
                return searchText.isEmpty ? "No episodes" : "No results"
            } else {
                return "\(filteredEpisodes.count) episode\(filteredEpisodes.count == 1 ? "" : "s")"
            }
        }
    }
    
    /// Check if content is empty
    var isEmpty: Bool {
        switch selectedViewType {
        case .shows, .grid: return filteredPodcasts.isEmpty
        case .episodes: return filteredEpisodes.isEmpty
        }
    }
    
    /// Check if search is active
    var isSearching: Bool {
        return !searchText.isEmpty
    }
    
    /// Get total episodes count
    var totalEpisodesCount: Int {
        return episodeController.getEpisodeCount()
    }
    
    /// Get total unplayed episodes count
    var totalUnplayedEpisodesCount: Int {
        return episodeController.getUnplayedEpisodesCount()
    }
} 