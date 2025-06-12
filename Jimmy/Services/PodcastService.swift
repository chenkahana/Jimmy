import Foundation

// Protocol for dependency injection
protocol PodcastServiceProtocol {
    func loadPodcasts() -> [Podcast]
    func addPodcast(_ podcast: Podcast) throws
}

/// PodcastService handles podcast management and episode fetching
class PodcastService: PodcastServiceProtocol {
    static let shared = PodcastService()
    
    private var podcasts: [Podcast] = []
    
    private init() {
        // Load podcasts from storage or other sources
        loadPodcastsFromStorage()
    }
    
    private func loadPodcastsFromStorage() {
        // Load podcasts from UserDefaults or file storage
        Task {
            do {
                if let data = UserDefaults.standard.data(forKey: "saved_podcasts") {
                    let decoder = JSONDecoder()
                    let loadedPodcasts = try decoder.decode([Podcast].self, from: data)
                    
                    await MainActor.run {
                        self.podcasts = loadedPodcasts
                        print("📚 PodcastService: Loaded \(loadedPodcasts.count) podcasts from storage")
                    }
                } else {
                    print("📚 PodcastService: No saved podcasts found, starting with empty array")
                }
            } catch {
                print("❌ PodcastService: Failed to load podcasts from storage: \(error)")
                // Start with empty array on error
                await MainActor.run {
                    self.podcasts = []
                }
            }
        }
    }
    
    func loadPodcasts() -> [Podcast] {
        return podcasts
    }
    
    func loadPodcastsAsync() async -> [Podcast] {
        return podcasts
    }
    
    func savePodcasts(_ podcasts: [Podcast]) {
        self.podcasts = podcasts
        
        // Persist to storage
        Task {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(podcasts)
                UserDefaults.standard.set(data, forKey: "saved_podcasts")
                print("📚 PodcastService: Saved \(podcasts.count) podcasts to storage")
            } catch {
                print("❌ PodcastService: Failed to save podcasts to storage: \(error)")
            }
        }
    }
    
    func fetchEpisodes(for podcast: Podcast, completion: @escaping ([Episode]) -> Void) {
        fetchEpisodesWithError(for: podcast) { episodes, error in
            completion(episodes)
        }
    }
    
    func fetchEpisodesWithError(for podcast: Podcast, completion: @escaping ([Episode], Error?) -> Void) {
        // Simple approach: just try to fetch from the URL, no validation needed
        print("🔄 PodcastService: Fetching episodes for \(podcast.title) from \(podcast.feedURL)")
        
        // Use RSSParser to fetch episodes from the podcast's RSS feed
        Task {
            do {
                let parser = RSSParser(podcastID: podcast.id)
                let (episodes, _) = try await parser.parse(from: podcast.feedURL)
                
                print("✅ PodcastService: Fetched \(episodes.count) episodes for \(podcast.title)")
                
                // Return episodes on main queue
                DispatchQueue.main.async {
                    completion(episodes, nil)
                }
            } catch {
                print("❌ Failed to fetch episodes for \(podcast.title): \(error.localizedDescription)")
                print("❌ Feed URL: \(podcast.feedURL)")
                
                // Log additional error details if available
                if let nsError = error as NSError? {
                    if let recoverySuggestion = nsError.localizedRecoverySuggestion {
                        print("💡 Suggestion: \(recoverySuggestion)")
                    }
                    print("🔍 Error domain: \(nsError.domain), code: \(nsError.code)")
                    
                    // Log specific network error codes for debugging
                    switch nsError.code {
                    case NSURLErrorTimedOut:
                        print("🕐 Specific error: Connection timed out")
                    case NSURLErrorCannotConnectToHost:
                        print("🔌 Specific error: Cannot connect to host")
                    case NSURLErrorNetworkConnectionLost:
                        print("📡 Specific error: Network connection lost")
                    case NSURLErrorDNSLookupFailed:
                        print("🌐 Specific error: DNS lookup failed")
                    case NSURLErrorNotConnectedToInternet:
                        print("📶 Specific error: Not connected to internet")
                    default:
                        print("❓ Other network error code: \(nsError.code)")
                    }
                }
                
                // Return empty array with error on main queue
                DispatchQueue.main.async {
                    completion([], error)
                }
            }
        }
    }
    
    /// Fetch episodes progressively using direct RSS parsing
    /// - Parameters:
    ///   - podcast: The podcast to fetch episodes for
    ///   - episodeCallback: Called for each episode as it's parsed (on main queue)
    ///   - metadataCallback: Called when podcast metadata is available (on main queue)
    ///   - completion: Called when all episodes are fetched or an error occurs
    func fetchEpisodesProgressively(for podcast: Podcast,
                                   episodeCallback: @escaping (Episode) -> Void,
                                   metadataCallback: @escaping (PodcastMetadata) -> Void,
                                   completion: @escaping ([Episode], Error?) -> Void) {
        
        print("🔄 PodcastService: Starting progressive fetch for \(podcast.title)")
        
        // Create parser and start progressive parsing directly
        let parser = RSSParser(podcastID: podcast.id)
        
        parser.parseProgressively(
            from: podcast.feedURL,
            episodeCallback: { episode in
                // This callback is already dispatched to main thread by RSSParser
                episodeCallback(episode)
                
                // OPTIMIZED: Removed excessive UIUpdateService calls that were causing main thread pressure
                // UIUpdateService will be notified in completion instead
            },
            metadataCallback: { metadata in
                // This callback is already dispatched to main thread by RSSParser
                metadataCallback(metadata)
                
                // OPTIMIZED: Only notify UIUpdateService for metadata once
                Task { @MainActor in
                    UIUpdateService.shared.handleEpisodeMetadataUpdate(
                        podcastId: podcast.id,
                        metadata: metadata
                    )
                }
            },
            completion: { result in
                // This completion is already dispatched to main thread by RSSParser
                switch result {
                case .success(let (episodes, _)):
                    print("✅ PodcastService: Progressive fetch completed with \(episodes.count) episodes for \(podcast.title)")
                    
                    // Notify UIUpdateService of completion on main actor
                    Task { @MainActor in
                        UIUpdateService.shared.handleEpisodeListCompleted(
                            podcastId: podcast.id,
                            episodes: episodes
                        )
                    }
                    
                    completion(episodes, nil)
                    
                case .failure(let error):
                    print("❌ Progressive fetch failed for \(podcast.title): \(error.localizedDescription)")
                    print("❌ Feed URL: \(podcast.feedURL)")
                    
                    // Log additional error details if available
                    if let nsError = error as NSError? {
                        if let recoverySuggestion = nsError.localizedRecoverySuggestion {
                            print("💡 Suggestion: \(recoverySuggestion)")
                        }
                        print("🔍 Error domain: \(nsError.domain), code: \(nsError.code)")
                    }
                    
                    completion([], error)
                }
            }
        )
    }
    
    func addPodcast(from url: URL) async throws -> Podcast {
        // Try to fetch podcast metadata from RSS feed
        do {
            let parser = RSSParser(podcastID: UUID())
            let (_, metadata) = try await parser.parse(from: url)
            
            let podcast = Podcast(
                title: metadata.title ?? "Unknown Podcast",
                author: metadata.author ?? "Unknown Author",
                description: metadata.description ?? "",
                feedURL: url,
                artworkURL: metadata.artworkURL
            )
            
            // Add to our podcasts list
            podcasts.append(podcast)
            
            return podcast
        } catch {
            print("❌ Failed to add podcast from URL \(url): \(error.localizedDescription)")
            throw error
        }
    }
    
    func addPodcast(_ podcast: Podcast) throws {
        podcasts.append(podcast)
        print("📚 PodcastService: Added podcast \(podcast.title)")
    }
    
    func clearAllSubscriptions() {
        podcasts.removeAll()
        print("🗑️ PodcastService: Cleared all subscriptions")
    }
    
    func downloadEpisode(_ episode: Episode, completion: @escaping (URL?) -> Void) {
        // Stub implementation
        print("⬇️ PodcastService: Downloading episode \(episode.title)")
        completion(nil)
    }
    
    func isEpisodeDownloaded(_ episode: Episode) -> Bool {
        // Stub implementation
        return false
    }
    
    func refreshAllPodcastArtwork(completion: @escaping (Int, Int) -> Void) {
        // Stub implementation
        print("🎨 PodcastService: Refreshing all podcast artwork")
        completion(0, 0)
    }
} 