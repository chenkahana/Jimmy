import Foundation
import SwiftUI
import Combine

// MARK: - Clean Architecture ViewModels
// Thin presentation layer that only handles UI state and delegates to use cases

/// Library ViewModel following clean architecture principles
@MainActor
final class CleanLibraryViewModel: ObservableObject {
    // MARK: - Published Properties (UI State Only)
    @Published private(set) var podcasts: [Podcast] = []
    @Published private(set) var episodes: [Episode] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    
    // UI-specific state
    @Published var searchText: String = ""
    @Published var selectedViewType: LibraryViewType = .grid
    @Published var isEditMode: Bool = false
    @Published var sortOrder: PodcastSortOrder = .lastEpisodeDate
    
    // MEMORY FIX: Limit episode array size to prevent memory issues
    private let maxEpisodesInMemory = 1000
    
    // MARK: - Use Cases (Business Logic)
    private let fetchPodcastsUseCase: FetchPodcastsUseCase
    private let subscribeToPodcastUseCase: SubscribeToPodcastUseCase
    private let unsubscribeFromPodcastUseCase: UnsubscribeFromPodcastUseCase
    private let refreshEpisodesUseCase: RefreshEpisodesUseCase
    
    // MARK: - Stores (Data Access)
    private let podcastStore: CleanPodcastStoreProtocol
    private let episodeStore: CleanEpisodeStoreProtocol
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(
        fetchPodcastsUseCase: FetchPodcastsUseCase,
        subscribeToPodcastUseCase: SubscribeToPodcastUseCase,
        unsubscribeFromPodcastUseCase: UnsubscribeFromPodcastUseCase,
        refreshEpisodesUseCase: RefreshEpisodesUseCase,
        podcastStore: CleanPodcastStoreProtocol,
        episodeStore: CleanEpisodeStoreProtocol
    ) {
        self.fetchPodcastsUseCase = fetchPodcastsUseCase
        self.subscribeToPodcastUseCase = subscribeToPodcastUseCase
        self.unsubscribeFromPodcastUseCase = unsubscribeFromPodcastUseCase
        self.refreshEpisodesUseCase = refreshEpisodesUseCase
        self.podcastStore = podcastStore
        self.episodeStore = episodeStore
        
        setupObservers()
        loadInitialData()
    }
    
    // MARK: - Public Interface (UI Actions)
    
    func refreshData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            _ = try await fetchPodcastsUseCase.execute()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func subscribeToPodcast(feedURL: URL) async {
        isLoading = true
        errorMessage = nil
        
        do {
            _ = try await subscribeToPodcastUseCase.execute(feedURL: feedURL)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func unsubscribeFromPodcast(_ podcast: Podcast) async {
        do {
            try await unsubscribeFromPodcastUseCase.execute(podcastID: podcast.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func refreshEpisodes(for podcastID: UUID) async {
        do {
            try await refreshEpisodesUseCase.execute(for: podcastID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Computed Properties (UI Logic Only)
    
    var filteredPodcasts: [Podcast] {
        searchText.isEmpty ? podcasts : podcasts.filter { podcast in
            podcast.title.localizedCaseInsensitiveContains(searchText) ||
            podcast.author.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var filteredEpisodes: [Episode] {
        let filtered = searchText.isEmpty ? episodes : episodes.filter { episode in
            episode.title.localizedCaseInsensitiveContains(searchText)
        }
        
        // MEMORY FIX: Limit the number of episodes returned to prevent memory issues
        let sorted = filtered.sorted { ($0.publishedDate ?? Date.distantPast) > ($1.publishedDate ?? Date.distantPast) }
        return Array(sorted.prefix(maxEpisodesInMemory))
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // Observe podcast changes from store
        podcastStore.changesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.updatePodcasts()
                }
            }
            .store(in: &cancellables)
        
        // Observe episode changes from store
        episodeStore.changesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.updateEpisodes()
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadInitialData() {
        Task {
            await updatePodcasts()
            await updateEpisodes()
        }
    }
    
    private func updatePodcasts() async {
        podcasts = await podcastStore.getAllPodcasts()
    }
    
    private func updateEpisodes() async {
        let allEpisodes = await episodeStore.getAllEpisodes()
        
        // MEMORY FIX: Only keep the most recent episodes in memory
        let recentEpisodes = Array(allEpisodes
            .sorted { ($0.publishedDate ?? Date.distantPast) > ($1.publishedDate ?? Date.distantPast) }
            .prefix(maxEpisodesInMemory))
        
        episodes = recentEpisodes
    }
    
    private func sortPodcasts(_ podcasts: [Podcast]) -> [Podcast] {
        switch sortOrder {
        case .title:
            return podcasts.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .author:
            return podcasts.sorted { $0.author.localizedCompare($1.author) == .orderedAscending }
        case .lastEpisodeDate:
            return podcasts.sorted { 
                ($0.lastEpisodeDate ?? Date.distantPast) > ($1.lastEpisodeDate ?? Date.distantPast)
            }
        case .subscriptionDate:
            return podcasts // Would need subscription date in model
        }
    }
}

/// Queue ViewModel following clean architecture principles
@MainActor
final class CleanQueueViewModel: ObservableObject {
    // MARK: - Published Properties (UI State Only)
    @Published private(set) var queue: [Episode] = []
    @Published private(set) var currentEpisode: Episode?
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    
    // MARK: - Store (Data Access)
    private let queueStore: QueueStore
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(queueStore: QueueStore) {
        self.queueStore = queueStore
        setupObservers()
        loadInitialData()
    }
    
    // MARK: - Public Interface (UI Actions)
    
    func addEpisode(_ episode: Episode) async {
        await queueStore.addEpisode(episode)
    }
    
    func removeEpisode(at index: Int) async {
        await queueStore.removeEpisode(at: index)
    }
    
    func moveEpisode(from sourceIndex: Int, to destinationIndex: Int) async {
        await queueStore.moveEpisode(from: sourceIndex, to: destinationIndex)
    }
    
    func playEpisode(at index: Int) async {
        await queueStore.setCurrentIndex(index)
    }
    
    func clearQueue() async {
        await queueStore.clearQueue()
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        queueStore.changesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.updateQueue()
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadInitialData() {
        Task {
            await updateQueue()
        }
    }
    
    private func updateQueue() async {
        queue = await queueStore.getQueue()
        currentEpisode = await queueStore.getCurrentEpisode()
        currentIndex = await queueStore.getCurrentIndex()
    }
}

/// Discovery ViewModel following clean architecture principles
@MainActor
final class CleanDiscoveryViewModel: ObservableObject {
    // MARK: - Published Properties (UI State Only)
    @Published private(set) var searchResults: [Podcast] = []
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var errorMessage: String?
    
    @Published var searchText: String = ""
    
    // MARK: - Use Cases (Business Logic)
    private let searchPodcastsUseCase: SearchPodcastsUseCase
    private let subscribeToPodcastUseCase: SubscribeToPodcastUseCase
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(
        searchPodcastsUseCase: SearchPodcastsUseCase,
        subscribeToPodcastUseCase: SubscribeToPodcastUseCase
    ) {
        self.searchPodcastsUseCase = searchPodcastsUseCase
        self.subscribeToPodcastUseCase = subscribeToPodcastUseCase
        
        setupSearchObserver()
    }
    
    // MARK: - Public Interface (UI Actions)
    
    func subscribeToPodcast(feedURL: URL) async {
        do {
            _ = try await subscribeToPodcastUseCase.execute(feedURL: feedURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Private Methods
    
    private func setupSearchObserver() {
        $searchText
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] searchText in
                Task { [weak self] in
                    await self?.performSearch(searchText)
                }
            }
            .store(in: &cancellables)
    }
    
    private func performSearch(_ query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        errorMessage = nil
        
        do {
            searchResults = try await searchPodcastsUseCase.execute(query: query)
        } catch {
            errorMessage = error.localizedDescription
            searchResults = []
        }
        
        isSearching = false
    }
}

// MARK: - Supporting Types

enum LibraryViewType: String, CaseIterable {
    case shows = "Shows"
    case grid = "Grid"
    case episodes = "Episodes"
    
    var displayName: String { rawValue }
}

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

// MARK: - Additional Use Cases

/// Use case for searching podcasts
struct SearchPodcastsUseCase {
    private let searchRepository: SearchRepositoryProtocol
    
    init(searchRepository: SearchRepositoryProtocol) {
        self.searchRepository = searchRepository
    }
    
    func execute(query: String) async throws -> [Podcast] {
        return try await searchRepository.searchPodcasts(query: query)
    }
}

/// Protocol for search operations
protocol SearchRepositoryProtocol {
    func searchPodcasts(query: String) async throws -> [Podcast]
} 