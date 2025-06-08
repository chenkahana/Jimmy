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
        // Use optimized service if available, fallback to original implementation
        if OptimizedPodcastService.shared.hasAttemptedLoad {
            OptimizedPodcastService.shared.fetchEpisodes(for: podcast, completion: completion)
            return
        }
        
        let url = podcast.feedURL

        // Create URLRequest with timeout configuration
        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0 // 15 second timeout
        request.cachePolicy = .useProtocolCachePolicy

        NetworkManager.shared.fetchData(with: request) { result in
            switch result {
            case .failure(let error):
                #if DEBUG
                print("⚠️ RSS Feed fetch error for \(podcast.title): \(error.localizedDescription)")
                #endif
                ErrorLogger.shared.log("RSS fetch error for \(podcast.title): \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion([])
                }
                return
            case .success(let data):
                #if DEBUG
                print("🌐 RSS Feed data received for \(podcast.title): \(data.count) bytes")
                #endif
                
                // Check if we received any data
                guard !data.isEmpty else {
                    #if DEBUG
                    print("⚠️ Empty RSS data received for \(podcast.title)")
                    #endif
                    ErrorLogger.shared.log("Empty RSS data for \(podcast.title)")
                    DispatchQueue.main.async {
                        completion([])
                    }
                    return
                }
                
                // Check if the data looks like valid XML
                if let dataString = String(data: data, encoding: .utf8) {
                    if !dataString.contains("<rss") && !dataString.contains("<feed") {
                        #if DEBUG
                        print("⚠️ RSS data doesn't appear to be valid XML for \(podcast.title)")
                        print("📄 First 200 characters: \(String(dataString.prefix(200)))")
                        #endif
                        ErrorLogger.shared.log("Invalid RSS format for \(podcast.title)")
                        DispatchQueue.main.async {
                            completion([])
                        }
                        return
                    }
                }
                
                let parser = RSSParser()
                let episodes = parser.parseRSS(data: data, podcastID: podcast.id) // Use podcast.id instead of random UUID

                #if DEBUG
                print("📊 RSS Parser returned \(episodes.count) episodes for \(podcast.title)")
                #endif

                // ALWAYS update podcast artwork from RSS channel data to ensure correct artwork
                // This prevents episode artwork from being used as podcast artwork
                if let artworkURLString = parser.getPodcastArtworkURL(),
                   let artworkURL = URL(string: artworkURLString) {
                    print("🎨 Auto-updating podcast artwork for \(podcast.title)")
                    print("   RSS Channel Artwork: \(artworkURL.absoluteString)")
                    self.updatePodcastArtwork(podcast: podcast, artworkURL: artworkURL)
                } else {
                    print("⚠️ No channel artwork found in RSS for \(podcast.title) - keeping existing artwork")
                }

                // Update the podcast's lastEpisodeDate with the most recent episode
                if let latestEpisodeDate = episodes.compactMap({ $0.publishedDate }).max() {
                    self.updatePodcastLastEpisodeDate(podcast: podcast, lastEpisodeDate: latestEpisodeDate)
                }

                DispatchQueue.main.async {
                    completion(episodes)
                }
            }
        }
    }

    // Update podcast artwork in saved podcasts
    private func updatePodcastArtwork(podcast: Podcast, artworkURL: URL) {
        loadPodcastsAsync { podcasts in
            var mutablePodcasts = podcasts
            if let index = mutablePodcasts.firstIndex(where: { $0.id == podcast.id }) {
                let oldURL = mutablePodcasts[index].artworkURL?.absoluteString ?? "nil"
                let newURL = artworkURL.absoluteString
                
                // Always update, even if URLs are the same (in case the image changed)
                mutablePodcasts[index].artworkURL = artworkURL
                self.savePodcasts(mutablePodcasts)
                
                if oldURL != newURL {
                    print("🎨 ✅ Updated artwork for '\(podcast.title)'")
                    print("   Old: \(oldURL)")
                    print("   New: \(newURL)")
                } else {
                    print("🎨 ℹ️ Refreshed artwork for '\(podcast.title)' (same URL)")
                }
            } else {
                print("⚠️ Podcast not found for artwork update: \(podcast.title)")
            }
        }
    }

    // Update podcast's last episode date in saved podcasts
    private func updatePodcastLastEpisodeDate(podcast: Podcast, lastEpisodeDate: Date) {
        loadPodcastsAsync { podcasts in
            var mutablePodcasts = podcasts
            if let index = mutablePodcasts.firstIndex(where: { $0.id == podcast.id }) {
                mutablePodcasts[index].lastEpisodeDate = lastEpisodeDate
                self.savePodcasts(mutablePodcasts)
            }
        }
    }

    // Force refresh podcast metadata (title, author, description, artwork) from RSS feed
    func refreshPodcastMetadata(for podcast: Podcast, completion: @escaping (Bool) -> Void) {
        print("🔍 Refreshing metadata for: \(podcast.title)")
        print("🎨 Current artwork URL: \(podcast.artworkURL?.absoluteString ?? "nil")")
        
        let request = URLRequest(url: podcast.feedURL)
        NetworkManager.shared.fetchData(with: request) { result in
            guard case let .success(data) = result else {
                if case let .failure(err) = result {
                    ErrorLogger.shared.log("Metadata refresh failed for \(podcast.title): \(err.localizedDescription)")
                }
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            let parser = RSSParser()
            _ = parser.parseRSS(data: data, podcastID: podcast.id)
            
            self.loadPodcastsAsync { podcasts in
                var mutablePodcasts = podcasts
                guard let index = mutablePodcasts.firstIndex(where: { $0.id == podcast.id }) else {
                    print("❌ Podcast not found in saved podcasts: \(podcast.title)")
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                
                var wasUpdated = false
                
                // Update artwork if available (ALWAYS update, even if current artwork exists)
                if let artworkURLString = parser.getPodcastArtworkURL(),
                   let artworkURL = URL(string: artworkURLString) {
                    let oldArtwork = mutablePodcasts[index].artworkURL?.absoluteString ?? "nil"
                    mutablePodcasts[index].artworkURL = artworkURL
                    wasUpdated = true
                    print("🎨 Updated artwork for \(podcast.title)")
                    print("   Old: \(oldArtwork)")
                    print("   New: \(artworkURL.absoluteString)")
                } else {
                    print("⚠️ No artwork URL found in RSS for \(podcast.title)")
                }
                
                // Update title if different
                if let newTitle = parser.getPodcastTitle(), newTitle != mutablePodcasts[index].title {
                    mutablePodcasts[index].title = newTitle
                    wasUpdated = true
                    print("📝 Updated title for \(podcast.title) -> \(newTitle)")
                }
                
                // Update author if different
                if let newAuthor = parser.getPodcastAuthor(), newAuthor != mutablePodcasts[index].author {
                    mutablePodcasts[index].author = newAuthor
                    wasUpdated = true
                    print("👤 Updated author for \(podcast.title) -> \(newAuthor)")
                }
                
                // Update description if different
                if let newDescription = parser.getPodcastDescription(), newDescription != mutablePodcasts[index].description {
                    mutablePodcasts[index].description = newDescription
                    wasUpdated = true
                    print("📄 Updated description for \(podcast.title)")
                }
                
                if wasUpdated {
                    self.savePodcasts(mutablePodcasts)
                } else {
                    print("ℹ️ No changes needed for \(podcast.title)")
                }
                
                DispatchQueue.main.async { completion(wasUpdated) }
            }
        }
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
        let request = URLRequest(url: feedURL)
        NetworkManager.shared.fetchData(with: request) { result in
            guard case let .success(data) = result else {
                if case let .failure(err) = result {
                    ErrorLogger.shared.log("Add podcast failed for \(feedURL.absoluteString): \(err.localizedDescription)")
                    completion(nil, err)
                } else {
                    completion(nil, PodcastServiceError.networkError)
                }
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
            self.loadPodcastsAsync { podcasts in
                var mutablePodcasts = podcasts
                mutablePodcasts.append(podcast)
                self.savePodcasts(mutablePodcasts)
                
                // Record this operation for undo
                ShakeUndoManager.shared.recordOperation(
                    .podcastSubscribed(podcast: podcast),
                    description: "Subscribed to \"\(podcast.title)\""
                )
                
                DispatchQueue.main.async {
                    completion(podcast, nil)
                }
            }
        }
    }

    // Force refresh all podcast artwork from RSS feeds
    func refreshAllPodcastArtwork(completion: @escaping (Int, Int) -> Void) {
        let podcasts = loadPodcasts()
        guard !podcasts.isEmpty else {
            completion(0, 0)
            return
        }
        
        print("🔄 Starting artwork refresh for \(podcasts.count) podcasts")
        
        let dispatchGroup = DispatchGroup()
        var updatedCount = 0
        var totalProcessed = 0
        
        for podcast in podcasts {
            dispatchGroup.enter()
            
            print("🔍 Processing: \(podcast.title)")
            
            let request = URLRequest(url: podcast.feedURL)
            NetworkManager.shared.fetchData(with: request) { result in
                defer {
                    totalProcessed += 1
                    dispatchGroup.leave()
                }

                guard case let .success(data) = result else {
                    if case let .failure(err) = result {
                        ErrorLogger.shared.log("Artwork refresh failed for \(podcast.title): \(err.localizedDescription)")
                    }
                    return
                }
                let parser = RSSParser()
                _ = parser.parseRSS(data: data, podcastID: podcast.id)
                
                if let artworkURLString = parser.getPodcastArtworkURL(),
                   let artworkURL = URL(string: artworkURLString) {
                    
                    self.loadPodcastsAsync { podcasts in
                        var mutablePodcasts = podcasts
                        if let index = mutablePodcasts.firstIndex(where: { $0.id == podcast.id }) {
                            let oldURL = mutablePodcasts[index].artworkURL?.absoluteString ?? "nil"
                            mutablePodcasts[index].artworkURL = artworkURL
                            self.savePodcasts(mutablePodcasts)
                            updatedCount += 1
                        }
                    }
                } else {
                    print("⚠️ No artwork found for \(podcast.title)")
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            print("🎨 Artwork refresh complete: \(updatedCount) of \(totalProcessed) updated")
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
