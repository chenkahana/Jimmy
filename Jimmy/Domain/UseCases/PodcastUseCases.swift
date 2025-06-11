import Foundation

// MARK: - Use Cases / Interactors Layer
// Contains business logic without UI or data layer dependencies

/// Use case for fetching and refreshing podcast data
struct FetchPodcastsUseCase {
    private let repository: PodcastRepositoryProtocol
    private let store: CleanPodcastStoreProtocol
    
    init(repository: PodcastRepositoryProtocol, store: CleanPodcastStoreProtocol) {
        self.repository = repository
        self.store = store
    }
    
    func execute() async throws -> [Podcast] {
        // Get cached podcasts first for immediate UI display
        let cachedPodcasts = await store.getAllPodcasts()
        
        // Fetch fresh data in background
        let freshPodcasts = try await repository.fetchPodcasts()
        
        // Calculate diff and update store
        let changes = calculateChanges(old: cachedPodcasts, new: freshPodcasts)
        await store.applyChanges(changes)
        
        return freshPodcasts
    }
    
    private func calculateChanges(old: [Podcast], new: [Podcast]) -> PodcastChanges {
        let oldDict = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let newDict = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        
        let added = new.filter { oldDict[$0.id] == nil }
        let removed = old.filter { newDict[$0.id] == nil }
        let updated = new.filter { podcast in
            if let oldPodcast = oldDict[podcast.id] {
                return oldPodcast != podcast
            }
            return false
        }
        
        return PodcastChanges(added: added, removed: removed, updated: updated)
    }
}

/// Use case for subscribing to a new podcast
struct SubscribeToPodcastUseCase {
    private let repository: PodcastRepositoryProtocol
    private let store: CleanPodcastStoreProtocol
    private let episodeStore: CleanEpisodeStoreProtocol
    
    init(repository: PodcastRepositoryProtocol, store: CleanPodcastStoreProtocol, episodeStore: CleanEpisodeStoreProtocol) {
        self.repository = repository
        self.store = store
        self.episodeStore = episodeStore
    }
    
    func execute(feedURL: URL) async throws -> Podcast {
        // Check if already subscribed
        let existingPodcasts = await store.getAllPodcasts()
        if existingPodcasts.contains(where: { $0.feedURL == feedURL }) {
            throw PodcastUseCaseError.alreadySubscribed
        }
        
        // Fetch podcast metadata and episodes
        let (podcast, episodes) = try await repository.fetchPodcastWithEpisodes(from: feedURL)
        
        // Add to store
        await store.addPodcast(podcast)
        await episodeStore.addEpisodes(episodes)
        
        return podcast
    }
}

/// Use case for unsubscribing from a podcast
struct UnsubscribeFromPodcastUseCase {
    private let repository: PodcastRepositoryProtocol
    private let store: CleanPodcastStoreProtocol
    private let episodeStore: CleanEpisodeStoreProtocol
    
    init(repository: PodcastRepositoryProtocol, store: CleanPodcastStoreProtocol, episodeStore: CleanEpisodeStoreProtocol) {
        self.repository = repository
        self.store = store
        self.episodeStore = episodeStore
    }
    
    func execute(podcastID: UUID) async throws {
        // Remove from stores
        await store.removePodcast(id: podcastID)
        await episodeStore.removeEpisodes(forPodcastID: podcastID)
        
        // Clean up repository data
        try await repository.deletePodcastData(id: podcastID)
    }
}

/// Use case for refreshing podcast episodes
struct RefreshEpisodesUseCase {
    private let repository: EpisodeRepositoryProtocol
    private let store: CleanEpisodeStoreProtocol
    
    init(repository: EpisodeRepositoryProtocol, store: CleanEpisodeStoreProtocol) {
        self.repository = repository
        self.store = store
    }
    
    func execute(for podcastID: UUID) async throws {
        // Get current episodes
        let currentEpisodes = await store.getEpisodes(forPodcastID: podcastID)
        
        // Fetch fresh episodes
        let freshEpisodes = try await repository.fetchEpisodes(for: podcastID)
        
        // Calculate diff and apply changes
        let changes = calculateEpisodeChanges(old: currentEpisodes, new: freshEpisodes)
        await store.applyEpisodeChanges(changes)
    }
    
    private func calculateEpisodeChanges(old: [Episode], new: [Episode]) -> CleanEpisodeChanges {
        let oldDict = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let newDict = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        
        let added = new.filter { oldDict[$0.id] == nil }
        let removed = old.filter { newDict[$0.id] == nil }
        let updated = new.filter { episode in
            if let oldEpisode = oldDict[episode.id] {
                return oldEpisode != episode
            }
            return false
        }
        
        return CleanEpisodeChanges(added: added, removed: removed, updated: updated)
    }
}

// MARK: - Change Models

struct PodcastChanges {
    let added: [Podcast]
    let removed: [Podcast]
    let updated: [Podcast]
    
    var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && updated.isEmpty
    }
}

struct CleanEpisodeChanges {
    let added: [Episode]
    let removed: [Episode]
    let updated: [Episode]
    
    var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && updated.isEmpty
    }
}

// MARK: - Error Types

enum PodcastUseCaseError: LocalizedError {
    case alreadySubscribed
    case invalidFeedURL
    case networkError
    case parsingError
    
    var errorDescription: String? {
        switch self {
        case .alreadySubscribed:
            return "Already subscribed to this podcast"
        case .invalidFeedURL:
            return "Invalid podcast feed URL"
        case .networkError:
            return "Network connection error"
        case .parsingError:
            return "Failed to parse podcast data"
        }
    }
} 