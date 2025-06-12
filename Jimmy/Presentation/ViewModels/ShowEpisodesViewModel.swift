import Foundation
import SwiftUI
import Combine

/// ViewModel for displaying a paginated list of episodes for a specific podcast.
///
/// This view model is responsible for orchestrating the fetching of episodes,
/// managing the UI state (loading, errors, etc.), and handling user interactions
/// like sorting, filtering, and searching.
@MainActor
final class ShowEpisodesViewModel: ObservableObject {
    
    // MARK: - Published UI State
    @Published var displayedEpisodes: [Episode] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var searchText: String = ""
    @Published var sortOrder: EpisodeSortOrder = .newestFirst
    @Published var filterType: EpisodeFilter = .all
    
    // MARK: - Public Properties
    var hasMorePages: Bool {
        return currentPage < totalPages - 1
    }

    // MARK: - Private State
    private(set) var podcast: Podcast
    private let paginatedService: PaginatedEpisodeService
    private var allEpisodes: [Episode] = []
    private var currentPage = 0
    private var totalPages = 1
    private let pageSize = 20
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(podcast: Podcast, paginatedService: PaginatedEpisodeService = PaginatedEpisodeService()) {
        self.podcast = podcast
        self.paginatedService = paginatedService
        
        setupBindings()
    }
    
    // MARK: - Public API
    
    /// Loads the initial set of episodes.
    func loadFirstPage() async {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        currentPage = 0
        
        do {
            let paginationState = try await paginatedService.fetchEpisodes(
                for: podcast,
                page: 0,
                pageSize: pageSize
            )
            
            allEpisodes = paginationState.episodes
            currentPage = paginationState.currentPage
            totalPages = (paginationState.totalCount + pageSize - 1) / pageSize
            applyFiltersAndSort()
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    /// Loads more episodes when the user scrolls to the end of the list.
    func loadNextPage() async {
        guard !isLoading, hasMorePages else { return }
        
        isLoading = true
        
        do {
            let nextPage = currentPage + 1
            let paginationState = try await paginatedService.fetchEpisodes(
                for: podcast,
                page: nextPage,
                pageSize: pageSize
            )
            
            allEpisodes.append(contentsOf: paginationState.episodes)
            currentPage = paginationState.currentPage
            totalPages = (paginationState.totalCount + pageSize - 1) / pageSize
            applyFiltersAndSort()
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    /// Checks if more episodes should be loaded based on the currently visible episode.
    func checkForLoadMore(episode: Episode) {
        guard let lastEpisode = displayedEpisodes.last, episode.id == lastEpisode.id else {
            return
        }
        
        Task {
            await loadNextPage()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Use Combine to react to changes in search, sort, and filter properties.
        Publishers.CombineLatest3($searchText, $sortOrder, $filterType)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyFiltersAndSort()
            }
            .store(in: &cancellables)
    }
    
    /// Applies the current search, filter, and sort criteria to the `allEpisodes` array
    /// and updates the `displayedEpisodes` property.
    private func applyFiltersAndSort() {
        var filtered = allEpisodes
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        
        // Apply content filter
        switch filterType {
        case .unplayed:
            filtered = filtered.filter { !$0.played }
        case .played:
            filtered = filtered.filter { $0.played }
        default:
            break
        }
        
        // Apply sort order
        switch sortOrder {
        case .newestFirst:
            filtered.sort(by: { ($0.publishedDate ?? Date.distantPast) > ($1.publishedDate ?? Date.distantPast) })
        case .oldestFirst:
            filtered.sort(by: { ($0.publishedDate ?? Date.distantPast) < ($1.publishedDate ?? Date.distantPast) })
        }
        
        self.displayedEpisodes = filtered
    }
}

// MARK: - Supporting Enums

extension ShowEpisodesViewModel {
    
    enum EpisodeSortOrder: String, CaseIterable, Identifiable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        
        var id: String { self.rawValue }
    }
    
    enum EpisodeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case unplayed = "Unplayed"
        case played = "Played"
        
        var id: String { self.rawValue }
    }
}