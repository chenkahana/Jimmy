import Foundation
import Combine

@MainActor
class PodcastSearchViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var searchScope: SearchScope = .all
    @Published var searchResults: [PodcastSearchResult] = []
    @Published var isSearching: Bool = false
    @Published var localPodcasts: [Podcast] = []
    @Published var showingSubscriptionAlert: Bool = false
    @Published var subscriptionMessage: String = ""

    enum SearchScope: String, CaseIterable {
        case all = "All"
        case subscribed = "Subscribed"
        case web = "Discover"
        
        var icon: String {
            switch self {
            case .all: return "magnifyingglass"
            case .subscribed: return "person.crop.circle"
            case .web: return "globe"
            }
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private let searchService: ITunesSearchServiceProtocol
    private let podcastService: PodcastServiceProtocol

    init(searchService: ITunesSearchServiceProtocol = iTunesSearchService.shared,
         podcastService: PodcastServiceProtocol = PodcastService.shared) {
        self.searchService = searchService
        self.podcastService = podcastService
        loadLocalPodcasts()
        setupSearchDebounce()
    }

    private func setupSearchDebounce() {
        $searchText
            .removeDuplicates()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] text in
                self?.performSearch()
            }
            .store(in: &cancellables)
    }

    func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        if searchScope == .subscribed {
            // Local search only
            return
        }
        isSearching = true
        Task {
            let results = await searchService.searchPodcasts(query: searchText)
            self.searchResults = results
            self.isSearching = false
        }
    }

    func loadLocalPodcasts() {
        localPodcasts = podcastService.loadPodcasts()
    }

    func isSubscribed(_ result: PodcastSearchResult) -> Bool {
        return localPodcasts.contains { $0.feedURL == result.feedURL }
    }

    func subscribe(to result: PodcastSearchResult) {
        let podcast = result.toPodcast()
        if isSubscribed(result) {
            subscriptionMessage = "Already subscribed to \(podcast.title)"
            showingSubscriptionAlert = true
            return
        }
        do {
            try podcastService.addPodcast(podcast)
            loadLocalPodcasts()
            subscriptionMessage = "Subscribed to \(podcast.title)"
            showingSubscriptionAlert = true
        } catch {
            subscriptionMessage = "Failed to subscribe: \(error.localizedDescription)"
            showingSubscriptionAlert = true
        }
    }

    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
} 