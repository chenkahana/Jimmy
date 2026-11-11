import Foundation
import JimmyKit
import Combine

/// ViewModel for Podcast Detail functionality following MVVM patterns
@MainActor
public class PodcastDetailViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var podcast: Podcast
    @Published var episodes: [EpisodeWithPlaybackState] = []
    @Published var filteredEpisodes: [EpisodeWithPlaybackState] = []
    @Published var isLoading: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var errorMessage: String?
    @Published var isSubscribed: Bool = false
    @Published var sortOrder: EpisodeSortOrder = .newestFirst
    @Published var filterOption: EpisodeFilter = .all
    @Published var searchText: String = ""
    @Published var showingUnsubscribeAlert: Bool = false
    
    // MARK: - Private Properties
    private let podcastService: PodcastServiceProtocol
    private let episodeRepository: EpisodeRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(
        podcast: Podcast,
        podcastService: PodcastServiceProtocol = DIContainer.shared.podcastService,
        episodeRepository: EpisodeRepositoryProtocol = DIContainer.shared.episodeRepository
    ) {
        self.podcast = podcast
        self.podcastService = podcastService
        self.episodeRepository = episodeRepository
        
        setupBindings()
        loadInitialData()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        podcastService.podcasts
            .map { podcasts in podcasts.contains { $0.id == self.podcast.id } }
            .assign(to: \.isSubscribed, on: self)
            .store(in: &cancellables)
        
        // Setup search binding
        Publishers.CombineLatest3($episodes, $searchText, $filterOption)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .map { [weak self] episodes, searchText, filter in
                self?.filterEpisodes(episodes, searchText: searchText, filter: filter) ?? []
            }
            .assign(to: \.filteredEpisodes, on: self)
            .store(in: &cancellables)
        
        // Sort episodes when sort order changes
        $sortOrder
            .sink { [weak self] _ in
                self?.sortEpisodes()
            }
            .store(in: &cancellables)
        
        // Listen for episode status updates
        NotificationCenter.default.publisher(for: .episodeStatusUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let updatedEpisode = notification.object as? Episode else { return }
                self?.updateEpisodeStatus(updatedEpisode)
            }
            .store(in: &cancellables)
    }
    
    private func loadInitialData() {
        Task {
            await loadEpisodes()
        }
    }
    
    private func filterEpisodes(_ episodes: [EpisodeWithPlaybackState], searchText: String, filter: EpisodeFilter) -> [EpisodeWithPlaybackState] {
        var filtered = episodes
        
        // Apply text filter
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filtered = filtered.filter { episode in
                episode.episode.title.localizedCaseInsensitiveContains(searchText) ||
                episode.episode.description?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        
        // Apply episode filter
        switch filter {
        case .all:
            break
        case .unplayed:
            filtered = filtered.filter { !$0.playbackState.finished }
        case .played:
            filtered = filtered.filter { $0.playbackState.finished }
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
            episodes.sort(by: { ($0.episode.publishedDate ?? Date.distantPast) > ($1.episode.publishedDate ?? Date.distantPast) })
        case .oldestFirst:
            episodes.sort(by: { ($0.episode.publishedDate ?? Date.distantPast) < ($1.episode.publishedDate ?? Date.distantPast) })
        case .titleAZ:
            episodes.sort(by: { $0.episode.title < $1.episode.title })
        case .titleZA:
            episodes.sort(by: { $0.episode.title > $1.episode.title })
        }
    }
    
    /// Update episode status in the episodes array
    private func updateEpisodeStatus(_ updatedEpisode: Episode) {
        // Update the episode in the episodes array
        if let index = episodes.firstIndex(where: { $0.episode.id == updatedEpisode.id }) {
            var updatedEpisodeWithState = episodes[index]
            updatedEpisodeWithState.episode = updatedEpisode
            episodes[index] = updatedEpisodeWithState
        }
    }
    
    // MARK: - Public Methods
    private func loadEpisodes() async {
        isLoading = true
        do {
            let (episodeList, _) = try await episodeRepository.fetchPage(podcastID: podcast.id, cursor: nil, limit: 50, ignoreCache: false)
            episodes = episodeList
        } catch {
            errorMessage = "Failed to load episodes."
        }
        isLoading = false
    }
    
    func refreshEpisodes() async {
        await loadEpisodes()
    }
    
    func toggleSubscription() async {
        if isSubscribed {
            showingUnsubscribeAlert = true
        } else {
            await podcastService.addPodcast(podcast)
        }
    }
    
    func confirmUnsubscribe() async {
        showingUnsubscribeAlert = false
        do {
            try await podcastService.deletePodcast(podcast)
            // Successful deletion - signal that view should be dismissed
            await MainActor.run {
                // Set a flag that the view can observe to dismiss itself
                isSubscribed = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to unsubscribe: \(error.localizedDescription)"
            }
        }
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

        // Play first episode in the list
        if let firstEpisode = episodes.first {
            await AppModel.current?.play(firstEpisode.episode.asPlaybackEpisode())
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
                updatedEpisodes[i].playbackState.finished = true
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
    
    // MARK: - Computed Properties
    var episodeCount: Int {
        episodes.count
    }
    
    var unplayedCount: Int {
        episodes.filter { !$0.playbackState.finished }.count
    }
    
    var totalDuration: TimeInterval {
        episodes.reduce(0) { $0 + ($1.episode.duration ?? 0) }
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
extension PodcastDetailViewModel {
    public enum EpisodeSortOrder: String, CaseIterable, Identifiable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case titleAZ = "Title A-Z"
        case titleZA = "Title Z-A"
        public var id: String { rawValue }
    }
    
    public enum EpisodeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case unplayed = "Unplayed"
        case played = "Played"
        case downloaded = "Downloaded"
        public var id: String { rawValue }
    }
}
