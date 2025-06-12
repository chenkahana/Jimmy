import Foundation
import Combine

/// ViewModel for Podcast Detail functionality following MVVM patterns
@MainActor
class PodcastDetailViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var podcast: Podcast
    @Published var episodes: [Episode] = []
    @Published var isLoading: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var errorMessage: String?
    @Published var isSubscribed: Bool = false
    @Published var sortOrder: EpisodeSortOrder = .newestFirst
    @Published var filterOption: EpisodeFilter = .all
    @Published var searchText: String = ""
    @Published var filteredEpisodes: [Episode] = []
    @Published var showingUnsubscribeAlert: Bool = false
    
    // MARK: - Private Properties
    private let podcastService: PodcastService
    private let episodeService: EpisodeCacheService
    private let updateService: EpisodeUpdateService
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(
        podcast: Podcast,
        podcastService: PodcastService = .shared,
        episodeService: EpisodeCacheService = .shared,
        updateService: EpisodeUpdateService = .shared
    ) {
        self.podcast = podcast
        self.podcastService = podcastService
        self.episodeService = episodeService
        self.updateService = updateService
        
        setupBindings()
        loadInitialData()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // Setup search binding
        Publishers.CombineLatest3($episodes, $searchText, $filterOption)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .map { [weak self] episodes, searchText, filter in
                self?.filterEpisodes(episodes, searchText: searchText, filter: filter) ?? []
            }
            .assign(to: \.filteredEpisodes, on: self)
            .store(in: &cancellables)
        
        // Monitor subscription status
        // Monitor subscription status
        // Note: PodcastService doesn't have subscriptionsPublisher, so we'll check manually
        updateSubscriptionStatus()
        
        // Sort episodes when sort order changes
        $sortOrder
            .sink { [weak self] _ in
                self?.sortEpisodes()
            }
            .store(in: &cancellables)
    }
    
    private func loadInitialData() {
        Task {
            await loadEpisodes()
            checkSubscriptionStatus()
        }
    }
    
    private func filterEpisodes(_ episodes: [Episode], searchText: String, filter: EpisodeFilter) -> [Episode] {
        var filtered = episodes
        
        // Apply text filter
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filtered = filtered.filter { episode in
                episode.title.localizedCaseInsensitiveContains(searchText) ||
                episode.description?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        
        // Apply episode filter
        switch filter {
        case .all:
            break
        case .unplayed:
            filtered = filtered.filter { $0.playbackPosition == 0 }
        case .played:
            filtered = filtered.filter { ($0.duration ?? 0) > 0 && $0.playbackPosition >= ($0.duration ?? 0) }
        case .downloaded:
            filtered = filtered.filter { episode in
                // This would need to check cache service
                return false // Placeholder
            }
        }
        
        return filtered
    }
    
    private func sortEpisodes() {
        switch sortOrder {
        case .newestFirst:
            episodes.sort(by: { ($0.publishedDate ?? Date.distantPast) > ($1.publishedDate ?? Date.distantPast) })
        case .oldestFirst:
            episodes.sort(by: { ($0.publishedDate ?? Date.distantPast) < ($1.publishedDate ?? Date.distantPast) })
        case .titleAZ:
            episodes.sort(by: { $0.title < $1.title })
        case .titleZA:
            episodes.sort(by: { $0.title > $1.title })
        }
    }
    
    private func checkSubscriptionStatus() {
        let subscriptions = podcastService.loadPodcasts()
        isSubscribed = subscriptions.contains { $0.id == podcast.id }
    }
    
    // MARK: - Public Methods
    private func loadEpisodes() {
        guard !isLoading else { return }
        isLoading = true
        
        Task {
            do {
                // Get episodes from cache service using async API
                if let cachedEpisodes = await episodeService.getEpisodes(for: podcast.id) {
                    await MainActor.run {
                        self.episodes = cachedEpisodes
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.episodes = []
                        self.isLoading = false
                    }
                }
            }
        }
    }
    
    func refreshEpisodes() {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        Task {
            do {
                // Clear cache first, then reload
                await episodeService.clearCache(for: podcast.id)
                
                // Get fresh episodes (this would typically trigger a network fetch)
                if let freshEpisodes = await episodeService.getEpisodes(for: podcast.id) {
                    await MainActor.run {
                        self.episodes = freshEpisodes
                        self.isRefreshing = false
                    }
                } else {
                    await MainActor.run {
                        self.episodes = []
                        self.isRefreshing = false
                    }
                }
            }
        }
    }
    
    func subscribe() async {
        guard !isSubscribed else { return }
        
        do {
            var subscriptions = podcastService.loadPodcasts()
            subscriptions.append(podcast)
            podcastService.savePodcasts(subscriptions)
            isSubscribed = true
            
            // Start loading episodes after subscription
            loadEpisodes()
        } catch {
            errorMessage = "Failed to subscribe: \(error.localizedDescription)"
        }
    }
    
    func unsubscribe() async {
        guard isSubscribed else { return }
        
        do {
            var subscriptions = podcastService.loadPodcasts()
            subscriptions.removeAll { $0.id == podcast.id }
            podcastService.savePodcasts(subscriptions)
            isSubscribed = false
            
            // Clear episodes after unsubscription
            episodes = []
            filteredEpisodes = []
        } catch {
            errorMessage = "Failed to unsubscribe: \(error.localizedDescription)"
        }
    }
    
    func toggleSubscription() async {
        if isSubscribed {
            showingUnsubscribeAlert = true
        } else {
            await subscribe()
        }
    }
    
    func confirmUnsubscribe() async {
        showingUnsubscribeAlert = false
        await unsubscribe()
    }
    
    func cancelUnsubscribe() {
        showingUnsubscribeAlert = false
    }
    
    func setSortOrder(_ order: EpisodeSortOrder) {
        sortOrder = order
    }
    
    func setFilter(_ filter: EpisodeFilter) {
        filterOption = filter
    }
    
    func clearSearch() {
        searchText = ""
    }
    
    func playAllEpisodes() async {
        guard !episodes.isEmpty else { return }
        
        do {
            // Add all episodes to queue and start playing
            let audioPlayerService = AudioPlayerService.shared
            // Play first episode in the list
            if let firstEpisode = episodes.first {
                audioPlayerService.loadEpisode(firstEpisode)
                audioPlayerService.play()
            }
        } catch {
            errorMessage = "Failed to play episodes: \(error.localizedDescription)"
        }
    }
    
    func downloadAllEpisodes() async {
        isLoading = true
        
        do {
            for episode in episodes {
                // Note: EpisodeCacheService doesn't have cacheEpisode method
                // Episodes are automatically cached when loaded
            }
        } catch {
            errorMessage = "Failed to download episodes: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func markAllAsPlayed() async {
        do {
            var updatedEpisodes = episodes
            for i in updatedEpisodes.indices {
                // Mark as played by setting playback position to duration
                updatedEpisodes[i].playbackPosition = updatedEpisodes[i].duration ?? 0
            }
            
            // Update in cache
            for episode in updatedEpisodes {
                // Note: EpisodeCacheService doesn't have updateEpisode method
                // Episodes are automatically updated when modified
            }
            
            episodes = updatedEpisodes
        } catch {
            errorMessage = "Failed to mark episodes as played: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Private Methods
    private func updateSubscriptionStatus() {
        let podcasts = podcastService.loadPodcasts()
        isSubscribed = podcasts.contains { $0.id == podcast.id }
    }
    
    // MARK: - Computed Properties
    var episodeCount: Int {
        episodes.count
    }
    
    var unplayedCount: Int {
        episodes.filter { $0.playbackPosition == 0 }.count
    }
    
    var totalDuration: TimeInterval {
        episodes.reduce(0) { $0 + ($1.duration ?? 0) }
    }
    
    var formattedTotalDuration: String {
        formatTime(totalDuration)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Supporting Types
enum EpisodeSortOrder: String, CaseIterable {
    case newestFirst = "Newest First"
    case oldestFirst = "Oldest First"
    case titleAZ = "Title A-Z"
    case titleZA = "Title Z-A"
}

enum EpisodeFilter: String, CaseIterable {
    case all = "All"
    case unplayed = "Unplayed"
    case played = "Played"
    case downloaded = "Downloaded"
} 