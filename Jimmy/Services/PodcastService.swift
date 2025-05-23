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
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                completion([])
                return
            }
            let parser = RSSParser()
            let episodes = parser.parseRSS(data: data, podcastID: podcast.id)
            // Update podcast artwork if available and not already set
            if let artworkURLString = parser.getPodcastArtworkURL(), let artworkURL = URL(string: artworkURLString), podcast.artworkURL == nil {
                self.updatePodcastArtwork(podcast: podcast, artworkURL: artworkURL)
            }
            completion(episodes)
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
} 