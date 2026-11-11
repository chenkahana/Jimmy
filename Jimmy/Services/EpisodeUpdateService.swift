import Foundation
import os.log

@MainActor
final class EpisodeUpdateService {
    static let shared = EpisodeUpdateService()
    
    private let podcastService: PodcastServiceProtocol
    private let podcastRepository: PodcastRepositoryProtocol
    private let episodeRepository: EpisodeRepositoryProtocol
    
    private var reloadTasks: [UUID: Task<Void, Never>] = [:]
    
    private init() {
        // Remove circular dependency by getting services from DIContainer
        self.podcastRepository = DIContainer.shared.podcastRepository
        self.episodeRepository = DIContainer.shared.episodeRepository
        
        // Get podcastService after DIContainer has initialized it
        self.podcastService = DIContainer.shared.podcastService
    }
    
    func reloadAll() async {
        let podcasts = await podcastService.getSubscribedPodcasts()
        
        for podcast in podcasts {
            await reload(podcastID: podcast.id)
        }
    }
    
    func forceUpdate() {
        Task {
            await reloadAll()
        }
    }
    
    func stopPeriodicUpdates() {
        // Stop any periodic update timers or background tasks
    }
    
    func reload(podcastID: UUID) async {
        // Check if task is already running (thread-safe)
        if reloadTasks[podcastID] != nil {
            return
        }
        
        let task = Task {
            // Cleanup happens automatically since we're on MainActor
            defer { 
                self.reloadTasks[podcastID] = nil
            }
            
            do {
                guard let podcast = try await podcastRepository.fetchPodcast(id: podcastID, ignoreCache: false) else {
                    return
                }
                
                // HEAD request with timeout
                let headers: HTTPURLResponse = try await withThrowingTaskGroup(of: HTTPURLResponse.self) { group in
                    group.addTask {
                        try await UnifiedNetworkService.shared.performHeadRequest(url: podcast.feedURL)
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 15_000_000_000)
                        throw CancellationError()
                    }
                    guard let result = try await group.next() else {
                        throw CancellationError()
                    }
                    group.cancelAll()
                    return result
                }
                
                let etag = headers.value(forHTTPHeaderField: "Etag")
                let lastModified = headers.value(forHTTPHeaderField: "Last-Modified")
                
                // Check if content has changed
                if let podcastEtag = podcast.etag, let responseEtag = etag, podcastEtag == responseEtag {
                    return
                }
                
                if let podcastLastFetched = podcast.lastFetched, let responseLastModified = lastModified {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                    if let lastModifiedDate = formatter.date(from: responseLastModified),
                       lastModifiedDate <= podcastLastFetched {
                        return
                    }
                }
                
                // RSS feed fetch with timeout
                let (fetchedPodcast, _): (Podcast, [Episode]) = try await withThrowingTaskGroup(of: (Podcast, [Episode]).self) { group in
                    group.addTask {
                        try await self.podcastRepository.fetchPodcastWithEpisodes(from: podcast.feedURL)
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 30_000_000_000)
                        throw CancellationError()
                    }
                    guard let result = try await group.next() else {
                        throw CancellationError()
                    }
                    group.cancelAll()
                    return result
                }
                
                // Update podcast metadata
                var updatedPodcast = podcast
                updatedPodcast.etag = etag
                updatedPodcast.lastFetched = Date()
                updatedPodcast.lastEpisodeDate = fetchedPodcast.lastEpisodeDate
                
                try await podcastRepository.savePodcasts([updatedPodcast])
                
            } catch {
                if error is CancellationError {
                } else {
                }
                // Don't rethrow - let the task complete gracefully
            }
        }
        
        // Store task (already on MainActor)
        self.reloadTasks[podcastID] = task
    }
}