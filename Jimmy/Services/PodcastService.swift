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
                print("⚠️ RSS Feed fetch error for \(podcast.title): \(error.localizedDescription)")
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
                    print("⚠️ RSS Feed HTTP error for \(podcast.title): \(httpResponse.statusCode)")
                    #endif
                    
                    DispatchQueue.main.async {
                        completion([])
                    }
                    return
                }
            }
            
            guard let data = data else {
                #if DEBUG
                print("⚠️ No data received for RSS feed: \(podcast.title)")
                #endif
                
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }
            
            let parser = RSSParser()
            let episodes = parser.parseRSS(data: data, podcastID: podcast.id) // Use podcast.id instead of random UUID
            
            // Update podcast artwork if available and not already set
            if let artworkURLString = parser.getPodcastArtworkURL(), 
               let artworkURL = URL(string: artworkURLString), 
               podcast.artworkURL == nil {
                self.updatePodcastArtwork(podcast: podcast, artworkURL: artworkURL)
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
            podcasts[index].artworkURL = artworkURL
            savePodcasts(podcasts)
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
            let podcast = Podcast(
                title: podcastTitle,
                author: podcastAuthor,
                description: description,
                feedURL: feedURL,
                artworkURL: artworkURL
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