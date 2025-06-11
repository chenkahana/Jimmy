import Foundation
import Combine

// MARK: - Store Protocols
// Define interfaces for thread-safe data stores

protocol CleanPodcastStoreProtocol {
    func getAllPodcasts() async -> [Podcast]
    func getPodcast(id: UUID) async -> Podcast?
    func addPodcast(_ podcast: Podcast) async
    func removePodcast(id: UUID) async
    func applyChanges(_ changes: PodcastChanges) async
    var changesPublisher: AnyPublisher<PodcastChanges, Never> { get }
}

protocol CleanEpisodeStoreProtocol {
    func getAllEpisodes() async -> [Episode]
    func getEpisodes(forPodcastID podcastID: UUID) async -> [Episode]
    func getEpisode(id: UUID) async -> Episode?
    func addEpisodes(_ episodes: [Episode]) async
    func removeEpisodes(forPodcastID podcastID: UUID) async
    func applyEpisodeChanges(_ changes: CleanEpisodeChanges) async
    var changesPublisher: AnyPublisher<CleanEpisodeChanges, Never> { get }
}

// MARK: - Actor-Based Stores
// Thread-safe data stores using Swift Actors

/// Thread-safe podcast store using Actor
actor CleanPodcastStore: CleanPodcastStoreProtocol {
    static let shared = CleanPodcastStore()
    
    private var podcasts: [UUID: Podcast] = [:]
    private let changesSubject = PassthroughSubject<PodcastChanges, Never>()
    
    private init() {}
    
    // MARK: - Public Interface
    
    func getAllPodcasts() async -> [Podcast] {
        return Array(podcasts.values).sorted { $0.title < $1.title }
    }
    
    func getPodcast(id: UUID) async -> Podcast? {
        return podcasts[id]
    }
    
    func addPodcast(_ podcast: Podcast) async {
        podcasts[podcast.id] = podcast
        let changes = PodcastChanges(added: [podcast], removed: [], updated: [])
        publishChanges(changes)
    }
    
    func removePodcast(id: UUID) async {
        guard let podcast = podcasts.removeValue(forKey: id) else { return }
        let changes = PodcastChanges(added: [], removed: [podcast], updated: [])
        publishChanges(changes)
    }
    
    func applyChanges(_ changes: PodcastChanges) async {
        // Apply additions
        for podcast in changes.added {
            podcasts[podcast.id] = podcast
        }
        
        // Apply updates
        for podcast in changes.updated {
            podcasts[podcast.id] = podcast
        }
        
        // Apply removals
        for podcast in changes.removed {
            podcasts.removeValue(forKey: podcast.id)
        }
        
        // Publish changes if not empty
        if !changes.isEmpty {
            publishChanges(changes)
        }
    }
    
    nonisolated var changesPublisher: AnyPublisher<PodcastChanges, Never> {
        changesSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func publishChanges(_ changes: PodcastChanges) {
        Task { @MainActor in
            changesSubject.send(changes)
        }
    }
}

/// Thread-safe episode store using Actor
actor CleanEpisodeStore: CleanEpisodeStoreProtocol {
    static let shared = CleanEpisodeStore()
    
    private var episodes: [UUID: Episode] = [:]
    private var podcastEpisodes: [UUID: Set<UUID>] = [:] // podcastID -> episodeIDs
    private let changesSubject = PassthroughSubject<CleanEpisodeChanges, Never>()
    
    // MEMORY FIX: Limit total episodes in memory
    private let maxEpisodesInMemory = 5000
    
    private init() {}
    
    // MARK: - Public Interface
    
    func getAllEpisodes() async -> [Episode] {
        // MEMORY FIX: Return only recent episodes to prevent memory issues
        let allEpisodes = Array(episodes.values).sorted { 
            ($0.publishedDate ?? Date.distantPast) > ($1.publishedDate ?? Date.distantPast)
        }
        return Array(allEpisodes.prefix(maxEpisodesInMemory))
    }
    
    func getEpisodes(forPodcastID podcastID: UUID) async -> [Episode] {
        guard let episodeIDs = podcastEpisodes[podcastID] else { return [] }
        return episodeIDs.compactMap { episodes[$0] }.sorted {
            ($0.publishedDate ?? Date.distantPast) > ($1.publishedDate ?? Date.distantPast)
        }
    }
    
    func getEpisode(id: UUID) async -> Episode? {
        return episodes[id]
    }
    
    func addEpisodes(_ newEpisodes: [Episode]) async {
        var addedEpisodes: [Episode] = []
        
        for episode in newEpisodes {
            // Only add if not already present
            if episodes[episode.id] == nil {
                episodes[episode.id] = episode
                addedEpisodes.append(episode)
                
                // Update podcast-episode mapping
                if let podcastID = episode.podcastID {
                    if podcastEpisodes[podcastID] == nil {
                        podcastEpisodes[podcastID] = Set()
                    }
                    podcastEpisodes[podcastID]?.insert(episode.id)
                }
            }
        }
        
        // MEMORY FIX: Clean up old episodes if we exceed the limit
        await cleanupOldEpisodesIfNeeded()
        
        if !addedEpisodes.isEmpty {
            let changes = CleanEpisodeChanges(added: addedEpisodes, removed: [], updated: [])
            publishChanges(changes)
        }
    }
    
    // MEMORY FIX: Clean up old episodes to prevent memory accumulation
    private func cleanupOldEpisodesIfNeeded() async {
        guard episodes.count > maxEpisodesInMemory else { return }
        
        // Sort episodes by date and keep only the most recent ones
        let sortedEpisodes = episodes.values.sorted { 
            ($0.publishedDate ?? Date.distantPast) > ($1.publishedDate ?? Date.distantPast)
        }
        
        let episodesToKeep = Array(sortedEpisodes.prefix(maxEpisodesInMemory))
        let episodeIDsToKeep = Set(episodesToKeep.map { $0.id })
        
        // Remove old episodes
        let removedEpisodes = episodes.values.filter { !episodeIDsToKeep.contains($0.id) }
        
        // Update episodes dictionary
        episodes = Dictionary(uniqueKeysWithValues: episodesToKeep.map { ($0.id, $0) })
        
        // Update podcast-episode mapping
        for (podcastID, episodeIDs) in podcastEpisodes {
            podcastEpisodes[podcastID] = episodeIDs.intersection(episodeIDsToKeep)
        }
        
        if !removedEpisodes.isEmpty {
            print("🧹 Cleaned up \(removedEpisodes.count) old episodes from memory")
        }
    }
    
    func removeEpisodes(forPodcastID podcastID: UUID) async {
        guard let episodeIDs = podcastEpisodes[podcastID] else { return }
        
        var removedEpisodes: [Episode] = []
        for episodeID in episodeIDs {
            if let episode = episodes.removeValue(forKey: episodeID) {
                removedEpisodes.append(episode)
            }
        }
        
        podcastEpisodes.removeValue(forKey: podcastID)
        
        if !removedEpisodes.isEmpty {
            let changes = CleanEpisodeChanges(added: [], removed: removedEpisodes, updated: [])
            publishChanges(changes)
        }
    }
    
    func applyEpisodeChanges(_ changes: CleanEpisodeChanges) async {
        // Apply additions
        for episode in changes.added {
            episodes[episode.id] = episode
            if let podcastID = episode.podcastID {
                if podcastEpisodes[podcastID] == nil {
                    podcastEpisodes[podcastID] = Set()
                }
                podcastEpisodes[podcastID]?.insert(episode.id)
            }
        }
        
        // Apply updates
        for episode in changes.updated {
            episodes[episode.id] = episode
        }
        
        // Apply removals
        for episode in changes.removed {
            episodes.removeValue(forKey: episode.id)
            if let podcastID = episode.podcastID {
                podcastEpisodes[podcastID]?.remove(episode.id)
                if podcastEpisodes[podcastID]?.isEmpty == true {
                    podcastEpisodes.removeValue(forKey: podcastID)
                }
            }
        }
        
        // Publish changes if not empty
        if !changes.isEmpty {
            publishChanges(changes)
        }
    }
    
    nonisolated var changesPublisher: AnyPublisher<CleanEpisodeChanges, Never> {
        changesSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func publishChanges(_ changes: CleanEpisodeChanges) {
        Task { @MainActor in
            changesSubject.send(changes)
        }
    }
}

/// Thread-safe queue store for episode playback queue
actor QueueStore {
    static let shared = QueueStore()
    
    private var queue: [Episode] = []
    private var currentIndex: Int = 0
    private let changesSubject = PassthroughSubject<QueueChanges, Never>()
    
    private init() {}
    
    // MARK: - Public Interface
    
    func getQueue() async -> [Episode] {
        return queue
    }
    
    func getCurrentEpisode() async -> Episode? {
        guard currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }
    
    func getCurrentIndex() async -> Int {
        return currentIndex
    }
    
    func addEpisode(_ episode: Episode) async {
        queue.append(episode)
        let changes = QueueChanges(added: [episode], removed: [], moved: [])
        publishChanges(changes)
    }
    
    func removeEpisode(at index: Int) async {
        guard index < queue.count else { return }
        let episode = queue.remove(at: index)
        
        // Adjust current index if needed
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex && currentIndex >= queue.count {
            currentIndex = max(0, queue.count - 1)
        }
        
        let changes = QueueChanges(added: [], removed: [episode], moved: [])
        publishChanges(changes)
    }
    
    func moveEpisode(from sourceIndex: Int, to destinationIndex: Int) async {
        guard sourceIndex < queue.count && destinationIndex < queue.count else { return }
        
        let episode = queue.remove(at: sourceIndex)
        queue.insert(episode, at: destinationIndex)
        
        // Adjust current index
        if sourceIndex == currentIndex {
            currentIndex = destinationIndex
        } else if sourceIndex < currentIndex && destinationIndex >= currentIndex {
            currentIndex -= 1
        } else if sourceIndex > currentIndex && destinationIndex <= currentIndex {
            currentIndex += 1
        }
        
        let changes = QueueChanges(added: [], removed: [], moved: [(episode, sourceIndex, destinationIndex)])
        publishChanges(changes)
    }
    
    func setCurrentIndex(_ index: Int) async {
        guard index < queue.count else { return }
        currentIndex = index
    }
    
    func clearQueue() async {
        let removedEpisodes = queue
        queue.removeAll()
        currentIndex = 0
        
        if !removedEpisodes.isEmpty {
            let changes = QueueChanges(added: [], removed: removedEpisodes, moved: [])
            publishChanges(changes)
        }
    }
    
    nonisolated var changesPublisher: AnyPublisher<QueueChanges, Never> {
        changesSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func publishChanges(_ changes: QueueChanges) {
        Task { @MainActor in
            changesSubject.send(changes)
        }
    }
}

// MARK: - Queue Changes Model

struct QueueChanges {
    let added: [Episode]
    let removed: [Episode]
    let moved: [(Episode, Int, Int)] // (episode, fromIndex, toIndex)
    
    var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && moved.isEmpty
    }
} 