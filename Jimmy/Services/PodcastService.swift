import Foundation

class PodcastService {
    static let shared = PodcastService()
    private let podcastsKey = "podcastsKey"
    
    // Save podcasts to UserDefaults
    func savePodcasts(_ podcasts: [Podcast]) {
        if let data = try? JSONEncoder().encode(podcasts) {
            UserDefaults.standard.set(data, forKey: podcastsKey)
            AppDataDocument.saveToICloudIfEnabled()
        }
    }
    
    // Load podcasts from UserDefaults
    func loadPodcasts() -> [Podcast] {
        if let data = UserDefaults.standard.data(forKey: podcastsKey),
           let podcasts = try? JSONDecoder().decode([Podcast].self, from: data) {
            return podcasts
        }
        return []
    }
    
    // Fetch episodes from a podcast RSS feed
    func fetchEpisodes(for podcast: Podcast, completion: @escaping ([Episode]) -> Void) {
        let url = podcast.feedURL
        
        // Create URLRequest with timeout configuration
        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0 // 15 second timeout
        request.cachePolicy = .useProtocolCachePolicy
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            // Handle timeout or network errors
            if let error = error {
                #if DEBUG
                AppLogger.error("⚠️ RSS Feed fetch error for \(podcast.title): \(error.localizedDescription)", category: .network)
                #endif
                
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }
            
            // Check HTTP response status
            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    #if DEBUG
                    AppLogger.error("⚠️ RSS Feed HTTP error for \(podcast.title): \(httpResponse.statusCode)", category: .network)
                    #endif
                    
                    DispatchQueue.main.async {
                        completion([])
                    }
                    return
                }
            }
            
            guard let data = data else {
                #if DEBUG
                AppLogger.error("⚠️ No data received for RSS feed: \(podcast.title)", category: .network)
                #endif
                
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }
            
            let parser = RSSParser()
            let episodes = parser.parseRSS(data: data, podcastID: podcast.id) // Use podcast.id instead of random UUID
            
            // ALWAYS update podcast artwork from RSS channel data to ensure correct artwork
            // This prevents episode artwork from being used as podcast artwork
            if let artworkURLString = parser.getPodcastArtworkURL(), 
               let artworkURL = URL(string: artworkURLString) {
                AppLogger.info("🎨 Auto-updating podcast artwork for \(podcast.title)", category: .network)
                AppLogger.info("   RSS Channel Artwork: \(artworkURL.absoluteString)", category: .network)
                self.updatePodcastArtwork(podcast: podcast, artworkURL: artworkURL)
            } else {
                AppLogger.info("⚠️ No channel artwork found in RSS for \(podcast.title) - keeping existing artwork", category: .network)
            }
            
            // Update the podcast's lastEpisodeDate with the most recent episode
            if let latestEpisodeDate = episodes.compactMap({ $0.publishedDate }).max() {
                self.updatePodcastLastEpisodeDate(podcast: podcast, lastEpisodeDate: latestEpisodeDate)
            }
            
            DispatchQueue.main.async {
                completion(episodes)
            }
        }
        task.resume()
    }

    // Update podcast artwork in saved podcasts
    private func updatePodcastArtwork(podcast: Podcast, artworkURL: URL) {
        var podcasts = loadPodcasts()
        if let index = podcasts.firstIndex(where: { $0.id == podcast.id }) {
            let oldURL = podcasts[index].artworkURL?.absoluteString ?? "nil"
            let newURL = artworkURL.absoluteString
            
            // Always update, even if URLs are the same (in case the image changed)
            podcasts[index].artworkURL = artworkURL
            savePodcasts(podcasts)
            
            if oldURL != newURL {
                AppLogger.info("🎨 ✅ Updated artwork for '\(podcast.title)'", category: .network)
                AppLogger.info("   Old: \(oldURL)", category: .network)
                AppLogger.info("   New: \(newURL)", category: .network)
            } else {
                AppLogger.info("🎨 ℹ️ Refreshed artwork for '\(podcast.title)' (same URL)", category: .network)
            }
        } else {
            AppLogger.info("⚠️ Podcast not found for artwork update: \(podcast.title)", category: .network)
        }
    }

    // Update podcast's last episode date in saved podcasts
    private func updatePodcastLastEpisodeDate(podcast: Podcast, lastEpisodeDate: Date) {
        var podcasts = loadPodcasts()
        if let index = podcasts.firstIndex(where: { $0.id == podcast.id }) {
            podcasts[index].lastEpisodeDate = lastEpisodeDate
            savePodcasts(podcasts)
        }
    }

    // Force refresh podcast metadata (title, author, description, artwork) from RSS feed
    func refreshPodcastMetadata(for podcast: Podcast, completion: @escaping (Bool) -> Void) {
        AppLogger.info("🔍 Refreshing metadata for: \(podcast.title)", category: .network)
        AppLogger.info("🎨 Current artwork URL: \(podcast.artworkURL?.absoluteString ?? "nil")", category: .network)
        
        URLSession.shared.dataTask(with: podcast.feedURL) { data, response, error in
            guard let data = data, error == nil else {
                AppLogger.error("❌ Failed to fetch RSS for \(podcast.title): \(error?.localizedDescription ?? "unknown error")", category: .network)
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            let parser = RSSParser()
            _ = parser.parseRSS(data: data, podcastID: podcast.id)
            
            var podcasts = self.loadPodcasts()
            guard let index = podcasts.firstIndex(where: { $0.id == podcast.id }) else {
                AppLogger.error("❌ Podcast not found in saved podcasts: \(podcast.title)", category: .network)
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            var wasUpdated = false
            
            // Update artwork if available (ALWAYS update, even if current artwork exists)
            if let artworkURLString = parser.getPodcastArtworkURL(),
               let artworkURL = URL(string: artworkURLString) {
                let oldArtwork = podcasts[index].artworkURL?.absoluteString ?? "nil"
                podcasts[index].artworkURL = artworkURL
                wasUpdated = true
                AppLogger.info("🎨 Updated artwork for \(podcast.title)", category: .network)
                AppLogger.info("   Old: \(oldArtwork)", category: .network)
                AppLogger.info("   New: \(artworkURL.absoluteString)", category: .network)
            } else {
                AppLogger.info("⚠️ No artwork URL found in RSS for \(podcast.title)", category: .network)
            }
            
            // Update title if different
            if let newTitle = parser.getPodcastTitle(), newTitle != podcasts[index].title {
                podcasts[index].title = newTitle
                wasUpdated = true
                AppLogger.info("📝 Updated title for \(podcast.title) -> \(newTitle)", category: .network)
            }
            
            // Update author if different  
            if let newAuthor = parser.getPodcastAuthor(), newAuthor != podcasts[index].author {
                podcasts[index].author = newAuthor
                wasUpdated = true
                AppLogger.info("👤 Updated author for \(podcast.title) -> \(newAuthor)", category: .network)
            }
            
            // Update description if different
            if let newDescription = parser.getPodcastDescription(), newDescription != podcasts[index].description {
                podcasts[index].description = newDescription
                wasUpdated = true
                AppLogger.info("📄 Updated description for \(podcast.title)", category: .network)
            }
            
            if wasUpdated {
                self.savePodcasts(podcasts)
                AppLogger.info("✅ Successfully updated metadata for \(podcast.title)", category: .network)
            } else {
                AppLogger.info("ℹ️ No changes needed for \(podcast.title)", category: .network)
            }
            
            DispatchQueue.main.async { completion(wasUpdated) }
        }.resume()
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
    func addPodcast(from feedURL: URL, completion: @escaping (Podcast?, Error?) -> Void) {
        // First, check if this podcast is already added
        let existingPodcasts = loadPodcasts()
        if existingPodcasts.contains(where: { $0.feedURL == feedURL }) {
            completion(nil, PodcastServiceError.podcastAlreadyExists)
            return
        }
        
        // Fetch and parse the RSS feed to validate it and get podcast info
        URLSession.shared.dataTask(with: feedURL) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil, error ?? PodcastServiceError.networkError)
                return
            }
            
            let parser = RSSParser()
            let episodes = parser.parseRSS(data: data, podcastID: UUID())
            
            // Extract podcast metadata from the RSS feed
            guard let podcastTitle = parser.getPodcastTitle(),
                  let podcastAuthor = parser.getPodcastAuthor() else {
                completion(nil, PodcastServiceError.invalidRSSFeed)
                return
            }
            
            // Create podcast object
            let artworkURL = parser.getPodcastArtworkURL().flatMap { URL(string: $0) }
            let description = parser.getPodcastDescription() ?? ""
            let latestEpisodeDate = episodes.compactMap({ $0.publishedDate }).max()
            
            let podcast = Podcast(
                title: podcastTitle,
                author: podcastAuthor,
                description: description,
                feedURL: feedURL,
                artworkURL: artworkURL,
                lastEpisodeDate: latestEpisodeDate
            )
            
            // Add to saved podcasts
            var podcasts = self.loadPodcasts()
            podcasts.append(podcast)
            self.savePodcasts(podcasts)
            
            DispatchQueue.main.async {
                completion(podcast, nil)
            }
        }.resume()
    }

    // Force refresh all podcast artwork from RSS feeds
    func refreshAllPodcastArtwork(completion: @escaping (Int, Int) -> Void) {
        let podcasts = loadPodcasts()
        guard !podcasts.isEmpty else {
            completion(0, 0)
            return
        }
        
        AppLogger.info("🔄 Starting artwork refresh for \(podcasts.count) podcasts", category: .network)
        
        let dispatchGroup = DispatchGroup()
        var updatedCount = 0
        var totalProcessed = 0
        
        for podcast in podcasts {
            dispatchGroup.enter()
            
            AppLogger.info("🔍 Processing: \(podcast.title)", category: .network)
            
            URLSession.shared.dataTask(with: podcast.feedURL) { data, response, error in
                defer {
                    totalProcessed += 1
                    dispatchGroup.leave()
                }
                
                guard let data = data, error == nil else {
                    AppLogger.error("❌ Failed to fetch RSS for \(podcast.title): \(error?.localizedDescription ?? "unknown")", category: .network)
                    return
                }
                
                let parser = RSSParser()
                _ = parser.parseRSS(data: data, podcastID: podcast.id)
                
                if let artworkURLString = parser.getPodcastArtworkURL(),
                   let artworkURL = URL(string: artworkURLString) {
                    
                    var podcasts = self.loadPodcasts()
                    if let index = podcasts.firstIndex(where: { $0.id == podcast.id }) {
                        let oldURL = podcasts[index].artworkURL?.absoluteString ?? "nil"
                        podcasts[index].artworkURL = artworkURL
                        self.savePodcasts(podcasts)
                        updatedCount += 1
                        
                        AppLogger.info("✅ Updated \(podcast.title)", category: .network)
                        AppLogger.info("   Old: \(oldURL)", category: .network)
                        AppLogger.info("   New: \(artworkURL.absoluteString)", category: .network)
                    }
                } else {
                    AppLogger.info("⚠️ No artwork found for \(podcast.title)", category: .network)
                }
            }.resume()
        }
        
        dispatchGroup.notify(queue: .main) {
            AppLogger.info("🎨 Artwork refresh complete: \(updatedCount) of \(totalProcessed) updated", category: .network)
            completion(updatedCount, totalProcessed)
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