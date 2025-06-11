import Foundation
import OSLog

class PodcastService: ObservableObject {
    static let shared = PodcastService()
    private(set) var hasAttemptedLoad: Bool = false
    private let podcastsKey = "podcastsKey"
    private let fileQueue = DispatchQueue(label: "com.jimmy.podcastService.fileQueue", qos: .background)
    
    // Save podcasts to UserDefaults
    func savePodcasts(_ podcasts: [Podcast]) {
        fileQueue.async {
            if let data = try? JSONEncoder().encode(podcasts) {
                UserDefaults.standard.set(data, forKey: self.podcastsKey)
                AppDataDocument.saveToICloudIfEnabled()
            }
        }
    }
    
    // Load podcasts from UserDefaults
    func loadPodcasts() -> [Podcast] {
        hasAttemptedLoad = true
        if let data = UserDefaults.standard.data(forKey: podcastsKey),
           let podcasts = try? JSONDecoder().decode([Podcast].self, from: data) {
            return podcasts
        }
        return []
    }
    
    // Load podcasts from UserDefaults - async version
    func loadPodcastsAsync(completion: @escaping ([Podcast]) -> Void) {
        hasAttemptedLoad = true
        fileQueue.async {
            if let data = UserDefaults.standard.data(forKey: self.podcastsKey),
               let podcasts = try? JSONDecoder().decode([Podcast].self, from: data) {
                DispatchQueue.main.async {
                    completion(podcasts)
                }
            } else {
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }
    
    // Load podcasts from UserDefaults - async/await version
    func loadPodcastsAsync() async -> [Podcast] {
        await withCheckedContinuation { continuation in
            loadPodcastsAsync { podcasts in
                continuation.resume(returning: podcasts)
            }
        }
    }
    
    // Fetch episodes from a podcast RSS feed
    func fetchEpisodes(for podcast: Podcast, completion: @escaping ([Episode]) -> Void) {
        OptimizedPodcastService.shared.fetchEpisodes(for: podcast, completion: completion)
    }

    // Force refresh podcast metadata (title, author, description, artwork) from RSS feed
    func refreshPodcastMetadata(for podcast: Podcast) async -> Bool {
        print("🔍 Refreshing metadata for: \(podcast.title)")
        let episodes = await OptimizedPodcastService.shared.fetchEpisodesAsync(for: podcast)
        return !episodes.isEmpty
    }

    // Download episode audio file
    func downloadEpisode(_ episode: Episode, completion: @escaping (URL?) -> Void) {
        guard let unwrappedAudioURL = episode.audioURL else {
            completion(nil)
            return
        }
        let task = URLSession.shared.downloadTask(with: unwrappedAudioURL) { tempURL, response, error in
            guard let tempURL = tempURL, error == nil else {
                completion(nil)
                return
            }
            let fileManager = FileManager.default
            let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let lastPathComponent = unwrappedAudioURL.lastPathComponent
            let destURL = docs.appendingPathComponent(lastPathComponent)
            do {
                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                try fileManager.moveItem(at: tempURL, to: destURL)
                completion(destURL)
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }

    // Check if episode is downloaded
    func isEpisodeDownloaded(_ episode: Episode) -> Bool {
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let unwrappedAudioURL = episode.audioURL else {
            return false
        }
        let lastPathComponent = unwrappedAudioURL.lastPathComponent
        let destURL = docs.appendingPathComponent(lastPathComponent)
        return fileManager.fileExists(atPath: destURL.path)
    }

    // Add a podcast from an RSS feed URL
    func addPodcast(from feedURL: URL) async throws -> Podcast {
        let existingPodcasts = await loadPodcastsAsync()
        if existingPodcasts.contains(where: { $0.feedURL == feedURL }) {
            throw PodcastServiceError.podcastAlreadyExists
        }
        
        // Generate a consistent podcast ID that will be used throughout
        let podcastID = UUID()
        let parser = RSSParser(podcastID: podcastID)
        
        let (episodes, metadata) = try await parser.parse(from: feedURL)
        
        guard let title = metadata.title, !title.isEmpty else {
            throw PodcastServiceError.invalidRSSFeed
        }
        
        // Create the podcast with the same ID used for parsing
        let newPodcast = Podcast(
            id: podcastID,  // Use the same ID that was used for parsing episodes
            title: title,
            author: metadata.author ?? "",
            description: metadata.description ?? "",
            feedURL: feedURL,
            artworkURL: metadata.artworkURL,
            lastEpisodeDate: episodes.compactMap({ $0.publishedDate }).max()
        )
        
        var allPodcasts = existingPodcasts
        allPodcasts.append(newPodcast)
        savePodcasts(allPodcasts)
        
        ShakeUndoManager.shared.recordOperation(
            .podcastSubscribed(podcast: newPodcast),
            description: "Subscribed to \"\(newPodcast.title)\""
        )
        
        // Update the cache with the newly fetched episodes (episodes already have correct podcast ID)
        EpisodeCacheService.shared.updateCache(episodes, for: newPodcast.id)
        
        return newPodcast
    }

    // Force refresh all podcast artwork from RSS feeds
    func refreshAllPodcastArtwork(completion: @escaping (Int, Int) -> Void) {
        let podcasts = loadPodcasts()
        guard !podcasts.isEmpty else {
            completion(0, 0)
            return
        }
        
        print("🔄 Starting artwork refresh for \(podcasts.count) podcasts")
        
        OptimizedPodcastService.shared.batchFetchEpisodes(for: podcasts) { _ in
            let totalProcessed = podcasts.count
            print("🎨 Artwork refresh complete: \(totalProcessed) podcasts processed")
            completion(totalProcessed, totalProcessed)
        }
    }
}

// MARK: - Error Types

enum PodcastServiceError: LocalizedError {
    case podcastAlreadyExists
    case networkError
    case invalidRSSFeed
    
    var errorDescription: String? {
        switch self {
        case .podcastAlreadyExists:
            return "This podcast is already in your library."
        case .networkError:
            return "Unable to connect to the podcast feed. Please check your internet connection."
        case .invalidRSSFeed:
            return "The URL does not contain a valid podcast RSS feed."
        }
    }
} 
