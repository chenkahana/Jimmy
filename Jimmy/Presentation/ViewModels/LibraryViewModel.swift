import Foundation
import Combine

/// ViewModel for Library functionality following MVVM patterns
@MainActor
class LibraryViewModel: ObservableObject {
    static let shared = LibraryViewModel()
    // MARK: - Published Properties
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var filteredPodcasts: [Podcast] = []
    @Published var filteredEpisodes: [Episode] = []
    @Published var allPodcasts: [Podcast] = []
    @Published var allEpisodes: [Episode] = []
    @Published var isEditMode: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private let podcastService: PodcastService
    private let episodeService: EpisodeCacheService
    private let paginatedEpisodeService: PaginatedEpisodeService
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(
        podcastService: PodcastService = .shared,
        episodeService: EpisodeCacheService = .shared,
        paginatedEpisodeService: PaginatedEpisodeService = .shared
    ) {
        self.podcastService = podcastService
        self.episodeService = episodeService
        self.paginatedEpisodeService = paginatedEpisodeService
        
        setupBindings()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] searchText in
                Task { [weak self] in
                    await self?.performSearch(searchText)
                }
            }
            .store(in: &cancellables)
    }
    
    private func performSearch(_ searchText: String) async {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            filteredPodcasts = allPodcasts
            filteredEpisodes = allEpisodes
            return
        }
        
        isLoading = true
        
        async let podcastsTask = searchPodcasts(query: searchText)
        async let episodesTask = searchEpisodes(query: searchText)
        
        let (podcasts, episodes) = await (podcastsTask, episodesTask)
        
        filteredPodcasts = podcasts
        filteredEpisodes = episodes
        errorMessage = nil
        
        isLoading = false
    }
    
    private func searchPodcasts(query: String) async -> [Podcast] {
        return await withCheckedContinuation { continuation in
            let filtered = allPodcasts.filter { podcast in
                podcast.title.localizedCaseInsensitiveContains(query) ||
                podcast.author.localizedCaseInsensitiveContains(query) ||
                podcast.description.localizedCaseInsensitiveContains(query)
            }
            continuation.resume(returning: filtered)
        }
    }
    
    private func searchEpisodes(query: String) async -> [Episode] {
        return await withCheckedContinuation { continuation in
            let filtered = allEpisodes.filter { episode in
                episode.title.localizedCaseInsensitiveContains(query) ||
                episode.description?.localizedCaseInsensitiveContains(query) == true
            }
            continuation.resume(returning: filtered)
        }
    }
    
    // MARK: - Public Methods
    func reloadData() async {
        isLoading = true
        
        await refreshPodcastData()
        await refreshEpisodeData()
        
        // Update filtered results based on current search
        if searchText.isEmpty {
            filteredPodcasts = allPodcasts
            filteredEpisodes = allEpisodes
        } else {
            await performSearch(searchText)
        }
        
        errorMessage = nil
        
        isLoading = false
    }
    
    func refreshPodcastData() async {
        allPodcasts = podcastService.loadPodcasts()
    }
    
    func refreshEpisodeData() async {
        // Load episodes using PaginatedEpisodeService which fetches from RSS feeds
        var allFetchedEpisodes: [Episode] = []
        
        for podcast in allPodcasts {
            do {
                // Use PaginatedEpisodeService to fetch episodes with proper RSS parsing
                let paginationState = try await paginatedEpisodeService.fetchEpisodes(
                    for: podcast,
                    page: 0,
                    pageSize: 50 // Get more episodes per podcast for library view
                )
                allFetchedEpisodes.append(contentsOf: paginationState.episodes)
            } catch {
                // If fetch fails, try to get from cache as fallback
                if let cachedEpisodes = await episodeService.getEpisodes(for: podcast.id) {
                    allFetchedEpisodes.append(contentsOf: cachedEpisodes)
                }
            }
        }
        
        allEpisodes = allFetchedEpisodes
    }
    
    func refreshAllData() async {
        // Immediately clear the local data to prevent showing stale episodes.
        allPodcasts = []
        allEpisodes = []
        filteredPodcasts = []
        filteredEpisodes = []
        
        await reloadData()
    }
    
    func toggleEditMode() {
        isEditMode.toggle()
    }
    
    func clearSearch() {
        searchText = ""
    }
    
    func getLatestEpisodeDate(for podcast: Podcast) -> Date? {
        let podcastEpisodes = allEpisodes.filter { $0.podcastID == podcast.id }
        return podcastEpisodes.compactMap { $0.publishedDate }.max()
    }
    
    func getEpisodesCount(for podcast: Podcast) -> Int {
        return allEpisodes.filter { $0.podcastID == podcast.id }.count
    }
    
    func getUnplayedEpisodesCount(for podcast: Podcast) -> Int {
        return allEpisodes.filter { $0.podcastID == podcast.id && !$0.played }.count
    }
    
    func deletePodcast(_ podcast: Podcast) async {
        var podcasts = podcastService.loadPodcasts()
        podcasts.removeAll { $0.id == podcast.id }
        podcastService.savePodcasts(podcasts)
        
        // Update local data
        allPodcasts.removeAll { $0.id == podcast.id }
        allEpisodes.removeAll { $0.podcastID == podcast.id }
        
        // Update filtered results
        if searchText.isEmpty {
            filteredPodcasts = allPodcasts
            filteredEpisodes = allEpisodes
        } else {
            await performSearch(searchText)
        }
    }
    
    func getPodcast(for episode: Episode) -> Podcast? {
        return allPodcasts.first { $0.id == episode.podcastID }
    }
} 