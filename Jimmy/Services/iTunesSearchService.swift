import Foundation

// Protocol for dependency injection
protocol ITunesSearchServiceProtocol {
    func searchPodcasts(query: String) async -> [PodcastSearchResult]
}

struct iTunesSearchService: ITunesSearchServiceProtocol {
    static let shared = iTunesSearchService()
    
    private init() {}
    
    // Search for podcasts using iTunes Search API
    func searchPodcasts(query: String, completion: @escaping ([PodcastSearchResult]) -> Void) {
        searchPodcastsWithRetry(query: query, retryCount: 0, completion: completion)
    }
    
    // Async version for protocol conformance
    func searchPodcasts(query: String) async -> [PodcastSearchResult] {
        return await withCheckedContinuation { continuation in
            searchPodcasts(query: query) { results in
                continuation.resume(returning: results)
            }
        }
    }
    
    private func searchPodcastsWithRetry(query: String, retryCount: Int, completion: @escaping ([PodcastSearchResult]) -> Void) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion([])
            return
        }
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // Check if query contains Hebrew characters
        let containsHebrew = query.unicodeScalars.contains { scalar in
            return (0x0590...0x05FF).contains(scalar.value)
        }
        
        // For Hebrew podcasts, search in Israeli iTunes store first, then global
        let searchURLs: [String]
        if containsHebrew {
            searchURLs = [
                "https://itunes.apple.com/search?term=\(encodedQuery)&media=podcast&entity=podcast&limit=50&country=IL",
                "https://itunes.apple.com/search?term=\(encodedQuery)&media=podcast&entity=podcast&limit=50"
            ]
        } else {
            searchURLs = [
                "https://itunes.apple.com/search?term=\(encodedQuery)&media=podcast&entity=podcast&limit=50"
            ]
        }
        
        // Try each search URL until we get results
        searchWithURLs(urls: searchURLs, retryCount: retryCount, completion: completion)
    }
    
    private func searchWithURLs(urls: [String], retryCount: Int, completion: @escaping ([PodcastSearchResult]) -> Void) {
        guard !urls.isEmpty else {
            completion([])
            return
        }
        
        let currentURL = urls[0]
        let remainingURLs = Array(urls.dropFirst())
        
        guard let url = URL(string: currentURL) else {
            searchWithURLs(urls: remainingURLs, retryCount: retryCount, completion: completion)
            return
        }

        Task {
            do {
                let data = try await UnifiedNetworkService.shared.fetchData(from: url)
                guard let response = try? JSONDecoder().decode(iTunesSearchResponse.self, from: data) else {
                    // Try next URL if available, otherwise retry current approach
                    if !remainingURLs.isEmpty {
                        searchWithURLs(urls: remainingURLs, retryCount: retryCount, completion: completion)
                        return
                    } else if retryCount < 2 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.searchWithURLs(urls: [currentURL], retryCount: retryCount + 1, completion: completion)
                        }
                        return
                    }
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                
                let results = response.results.compactMap { result -> PodcastSearchResult? in
                    guard let feedUrl = URL(string: result.feedUrl ?? "") else { return nil }
                    
                    // Create better artwork URL with fallback chain
                    let artworkURL = self.createBestArtworkURL(from: result)
                    
                    return PodcastSearchResult(
                        id: result.collectionId,
                        title: result.collectionName,
                        author: result.artistName,
                        feedURL: feedUrl,
                        artworkURL: artworkURL,
                        description: result.description,
                        genre: result.primaryGenreName,
                        trackCount: result.trackCount
                    )
                }
                
                // If we got results, return them. Otherwise try next URL if available
                if !results.isEmpty || remainingURLs.isEmpty {
                    DispatchQueue.main.async { completion(results) }
                } else {
                    searchWithURLs(urls: remainingURLs, retryCount: retryCount, completion: completion)
                }
            } catch {
                // Try next URL if available, otherwise retry current approach
                if !remainingURLs.isEmpty {
                    searchWithURLs(urls: remainingURLs, retryCount: retryCount, completion: completion)
                } else if retryCount < 2 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.searchWithURLs(urls: [currentURL], retryCount: retryCount + 1, completion: completion)
                    }
                } else {
                    DispatchQueue.main.async { completion([]) }
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
        
        Task {
            do {
                let data = try await UnifiedNetworkService.shared.fetchData(from: url)
                let response = try JSONDecoder().decode(iTunesSearchResponse.self, from: data)
                if let result = response.results.first,
                   let feedUrl = URL(string: result.feedUrl ?? "") {
                    
                    let podcastResult = PodcastSearchResult(
                        id: result.collectionId,
                        title: result.collectionName,
                        author: result.artistName,
                        feedURL: feedUrl,
                        artworkURL: self.createBestArtworkURL(from: result),
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

struct PodcastSearchResult: Identifiable, Codable {
    let id: Int
    let title: String
    let author: String
    let feedURL: URL
    let artworkURL: URL?
    let description: String?
    let genre: String
    let trackCount: Int
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

        Task {
            do {
                let data = try await UnifiedNetworkService.shared.fetchData(from: url)
                if let searchResponse = try? JSONDecoder().decode(iTunesEpisodeSearchResponse.self, from: data) {
                    let match = searchResponse.results.first { $0.collectionId == podcastId }
                    DispatchQueue.main.async { completion(match) }
                } else {
                    DispatchQueue.main.async { completion(nil) }
                }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
    
    private func createBestArtworkURL(from result: iTunesPodcastResult) -> URL? {
        // Try artwork URLs in order of preference (highest resolution first)
        let artworkOptions = [
            result.artworkUrl600,
            result.artworkUrl100,
            result.artworkUrl60,
            result.artworkUrl30,
            result.artworkUrl
        ].compactMap { $0 }
        
        for artworkString in artworkOptions {
            if !artworkString.isEmpty, let url = URL(string: artworkString) {
                return url
            }
        }
        
        return nil
    }
}
