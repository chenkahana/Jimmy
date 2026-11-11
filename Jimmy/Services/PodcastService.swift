import Foundation
import Combine

// Protocol for dependency injection
protocol PodcastServiceProtocol {
    func getSubscribedPodcasts() async -> [Podcast]
    func loadPodcasts() -> [Podcast]
    func addPodcast(from feedURL: URL) async throws -> (Podcast, [Episode])
    func addPodcast(_ podcast: Podcast) async
    func updatePodcast(_ podcast: Podcast) async throws
    func deletePodcast(_ podcast: Podcast) async throws
    func removePodcast(id: UUID) async throws
    func refreshAllPodcasts() async
    
    var podcasts: AnyPublisher<[Podcast], Never> { get }
}

/// PodcastService coordinates podcast management and episode fetching, acting as a bridge between the UI and the data layer.
class PodcastService: PodcastServiceProtocol {
    // Remove circular dependency - shared will be initialized by DIContainer
    static var shared: PodcastService!
    
    private let podcastRepository: PodcastRepositoryProtocol
    private let episodeRepository: EpisodeRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // Shared integration layer for coordinated fetching and subscription flows.
    private let worldClassIntegration = WorldClassIntegration.shared
    
    private let podcastSubject = CurrentValueSubject<[Podcast], Never>([])
    
    var podcasts: AnyPublisher<[Podcast], Never> {
        podcastSubject.eraseToAnyPublisher()
    }
    
    // Make initializer public for dependency injection
    init(
        podcastRepository: PodcastRepositoryProtocol,
        episodeRepository: EpisodeRepositoryProtocol
    ) {
        self.podcastRepository = podcastRepository
        self.episodeRepository = episodeRepository
        
        // Load initial podcasts and subscribe to changes
        Task {
            await loadInitialPodcasts()
            subscribeToRepositoryChanges()
        }
    }
    
    private func loadInitialPodcasts() async {
        do {
            let podcasts = try await podcastRepository.fetchPodcasts(ignoreCache: false)
            await MainActor.run {
                podcastSubject.send(podcasts)
            }
        } catch {
            Log.data.error("PodcastService-LoadInitial failed: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                podcastSubject.send([])
            }
        }
    }
    
    private func subscribeToRepositoryChanges() {
        podcastRepository.podcastChangesPublisher
            .sink { [weak self] _ in
                Task {
                    await self?.loadInitialPodcasts()
                }
            }
            .store(in: &cancellables)
    }

    func getSubscribedPodcasts() async -> [Podcast] {
        // Use the shared integration layer for coordinated fetching.
        do {
            return try await worldClassIntegration.fetchPodcasts(forceRefresh: false)
        } catch {
            Log.data.error("PodcastService-GetSubscribed failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
    
    /// Load podcasts from database only - NO network calls
    /// This is used for fast library loading
    private func loadPodcastsFromDatabaseOnly() async -> [Podcast] {
        do {
            let podcasts = try await podcastRepository.fetchPodcasts(ignoreCache: false)
            podcastSubject.send(podcasts)
            return podcasts
        } catch {
            return []
        }
    }
    
    func loadPodcasts() -> [Podcast] {
        return podcastSubject.value
    }
    
    func loadPodcastsAsync() async -> [Podcast] {
        return await getSubscribedPodcasts()
    }
    
    func addPodcast(from feedURL: URL) async throws -> (Podcast, [Episode]) {
        // Use the shared integration layer for subscription and initial episode fetch.
        let result = try await worldClassIntegration.subscribe(to: feedURL)

        Log.data.info("Podcast subscribe: \(result.0.id.uuidString, privacy: .public)")

        return result
    }
    
    func addPodcast(_ podcast: Podcast) async {
        do {
            try await podcastRepository.addPodcast(podcast)
        } catch {
            Log.data.error("PodcastService-AddPodcast failed for \(podcast.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func updatePodcast(_ podcast: Podcast) async throws {
        try await podcastRepository.updatePodcast(podcast)
    }
    
    func deletePodcast(_ podcast: Podcast) async throws {
        do {
            try await podcastRepository.deletePodcastData(id: podcast.id)

            Log.data.info("Podcast unsubscribe: \(podcast.id.uuidString, privacy: .public)")
        } catch {
            Log.data.error("PodcastService-DeletePodcast failed for \(podcast.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func removePodcast(id: UUID) async throws {
        do {
            try await podcastRepository.deletePodcastData(id: id)
        } catch {
            Log.data.error("PodcastService-RemovePodcast failed for \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func getEpisodes(for id: UUID) async -> [Episode] {
        do {
            let (episodesWithState, _) = try await episodeRepository.fetchPage(podcastID: id, cursor: nil, limit: 50, ignoreCache: false)
            return episodesWithState.map { $0.episode }
        } catch {
            Log.data.error("PodcastService-GetEpisodes failed for \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
    
    func refreshAllPodcasts() async {
        do {
            let podcasts = try await podcastRepository.fetchPodcasts(ignoreCache: true)
            await MainActor.run {
                podcastSubject.send(podcasts)
            }
        } catch {
        }
    }
    
    /// Refresh a single podcast with proper error handling
    private func refreshSinglePodcast(_ podcast: Podcast) async {
        do {
            
            // Use EpisodeUpdateService for the actual refresh logic
            await EpisodeUpdateService.shared.reload(podcastID: podcast.id)
            
        } catch {
            // Don't throw - continue with other podcasts
        }
    }
    
    func savePodcasts(_ podcasts: [Podcast]) {
        // Save podcasts to storage
        for podcast in podcasts {
            Task {
                await addPodcast(podcast)
            }
        }
    }
    
    // MARK: - Episode Download Status
    
    /// Checks if an episode is downloaded locally
    func isEpisodeDownloaded(_ episode: Episode) -> Bool {
        // Check if the episode has a local file URL and the file exists
        guard let localURL = episode.localFileURL else { return false }
        return FileManager.default.fileExists(atPath: localURL.path)
    }
    
    // MARK: - Title Cleanup Utility
    
    /// Fixes duplicated titles in existing podcast records
    func fixDuplicatedTitles() async {
        
        do {
            let allPodcasts = await getSubscribedPodcasts()
            var updatedPodcasts: [Podcast] = []
            
            for podcast in allPodcasts {
                let newCleanTitle = Podcast.processCleanTitle(from: podcast.title)
                
                // Only update if the cleanTitle needs fixing
                if newCleanTitle != podcast.cleanTitle {
                    var updatedPodcast = podcast
                    updatedPodcast.cleanTitle = newCleanTitle
                    updatedPodcasts.append(updatedPodcast)
                }
            }
            
            if !updatedPodcasts.isEmpty {
                try await podcastRepository.savePodcasts(updatedPodcasts)
            } else {
            }
            
        } catch {
        }
    }
} 
