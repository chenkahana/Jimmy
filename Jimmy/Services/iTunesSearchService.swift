import Foundation

struct iTunesSearchService {
    static let shared = iTunesSearchService()
    
    private init() {}
    
    // Search for podcasts using iTunes Search API
    func searchPodcasts(query: String, completion: @escaping ([PodcastSearchResult]) -> Void) {
        searchPodcastsWithRetry(query: query, retryCount: 0, completion: completion)
    }
    
    private func searchPodcastsWithRetry(query: String, retryCount: Int, completion: @escaping ([PodcastSearchResult]) -> Void) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion([])
            return
        }
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://itunes.apple.com/search?term=\(encodedQuery)&media=podcast&entity=podcast&limit=50"
        
        guard let url = URL(string: urlString) else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0 // 10 second timeout
        request.cachePolicy = .useProtocolCachePolicy

        NetworkManager.shared.fetchData(with: request, retries: 2) { result in
            guard case let .success(data) = result else {
                if case let .failure(err) = result, case NetworkError.offline = err {
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                if retryCount < 2 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.searchPodcastsWithRetry(query: query, retryCount: retryCount + 1, completion: completion)
                    }
                    return
                }
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            do {
                let searchResponse = try JSONDecoder().decode(iTunesSearchResponse.self, from: data)
                let podcastResults = searchResponse.results.compactMap { result -> PodcastSearchResult? in
                    // Validate that we have required fields
                    guard !result.collectionName.isEmpty,
                          !result.artistName.isEmpty,
                          let feedUrlString = result.feedUrl,
                          !feedUrlString.isEmpty,
                          let feedUrl = URL(string: feedUrlString) else { 
                        return nil 
                    }
                    
                    return PodcastSearchResult(
                        id: result.collectionId,
                        title: result.collectionName,
                        author: result.artistName,
                        feedURL: feedUrl,
                        artworkURL: URL(string: result.artworkUrl600 ?? result.artworkUrl100 ?? ""),
                        description: result.description,
                        genre: result.primaryGenreName,
                        trackCount: result.trackCount
                    )
                }
                
                DispatchQueue.main.async {
                    completion(podcastResults)
                }
            } catch {
                #if DEBUG
                print("⚠️ iTunes Search API parsing error: \(error.localizedDescription)")
                #endif
                
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }
    
    // Get podcast details by iTunes ID
    func getPodcastDetails(iTunesId: Int, completion: @escaping (PodcastSearchResult?) -> Void) {
        let urlString = "https://itunes.apple.com/lookup?id=\(iTunesId)&entity=podcast"
        
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        let request = URLRequest(url: url)

        NetworkManager.shared.fetchData(with: request) { result in
            guard case let .success(data) = result else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            do {
                let response = try JSONDecoder().decode(iTunesSearchResponse.self, from: data)
                if let result = response.results.first,
                   let feedUrl = URL(string: result.feedUrl ?? "") {
                    
                    let podcastResult = PodcastSearchResult(
                        id: result.collectionId,
                        title: result.collectionName,
                        author: result.artistName,
                        feedURL: feedUrl,
                        artworkURL: URL(string: result.artworkUrl600 ?? result.artworkUrl100 ?? ""),
                        description: result.description,
                        genre: result.primaryGenreName,
                        trackCount: result.trackCount
                    )
                    
                    DispatchQueue.main.async {
                        completion(podcastResult)
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}

// MARK: - Data Models

struct iTunesSearchResponse: Codable {
    let resultCount: Int
    let results: [iTunesPodcastResult]
}

struct iTunesPodcastResult: Codable {
    let wrapperType: String
    let kind: String
    let collectionId: Int
    let trackId: Int
    let artistName: String
    let collectionName: String
    let trackName: String
    let collectionCensoredName: String
    let trackCensoredName: String
    let collectionViewUrl: String
    let feedUrl: String?
    let trackViewUrl: String
    let artworkUrl30: String?
    let artworkUrl60: String?
    let artworkUrl100: String?
    let artworkUrl600: String?
    let collectionPrice: Double?
    let trackPrice: Double?
    let releaseDate: String
    let collectionExplicitness: String
    let trackExplicitness: String
    let trackCount: Int
    let trackTimeMillis: Int?
    let country: String
    let currency: String
    let primaryGenreName: String
    let contentAdvisoryRating: String?
    let artworkUrl: String?
    let description: String?
    let genreIds: [String]?
    let genres: [String]?
}

struct PodcastSearchResult: Identifiable {
    let id: Int
    let title: String
    let author: String
    let feedURL: URL
    let artworkURL: URL?
    let description: String?
    let genre: String
    let trackCount: Int
    
    // Convert to Podcast model
    func toPodcast() -> Podcast {
        let cleanedDescription = description?.cleanedEpisodeDescription ?? ""
        return Podcast(
            title: title,
            author: author,
            description: cleanedDescription,
            feedURL: feedURL,
            artworkURL: artworkURL
        )
    }
}

// MARK: - Episode Search Models

struct iTunesEpisodeSearchResponse: Codable {
    let resultCount: Int
    let results: [iTunesEpisodeResult]
}

struct iTunesEpisodeResult: Codable {
    let collectionId: Int
    let collectionName: String
    let trackId: Int
    let trackName: String
    let trackViewUrl: String
}

extension iTunesSearchService {
    /// Search for an episode within a specific podcast.
    /// - Parameters:
    ///   - podcastId: iTunes collection ID of the podcast.
    ///   - episodeTitle: Title of the episode to look up.
    ///   - completion: Callback with optional episode result.
    func searchEpisode(podcastId: Int, episodeTitle: String, completion: @escaping (iTunesEpisodeResult?) -> Void) {
        let trimmed = episodeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(nil)
            return
        }

        let encodedQuery = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://itunes.apple.com/search?term=\(encodedQuery)&entity=podcastEpisode&limit=50"

        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0

        NetworkManager.shared.fetchData(with: request) { result in
            guard case let .success(data) = result else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            if let searchResponse = try? JSONDecoder().decode(iTunesEpisodeSearchResponse.self, from: data) {
                let match = searchResponse.results.first { $0.collectionId == podcastId }
                DispatchQueue.main.async { completion(match) }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
}
