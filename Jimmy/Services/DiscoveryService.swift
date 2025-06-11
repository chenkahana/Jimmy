import Foundation

struct TrendingEpisode: Identifiable, Codable {
    let id: Int
    let title: String
    let podcastName: String
    let feedURL: URL
    let artworkURL: URL?
}

/// Service responsible for fetching top charts, featured podcasts and trending episodes
class DiscoveryService {
    static let shared = DiscoveryService()
    private init() {}

    private let baseURL = "https://rss.applemarketingtools.com/api/v2/us/podcasts"

    func fetchTopCharts(limit: Int = 100, completion: @escaping ([PodcastSearchResult]) -> Void) {
        let url = URL(string: "\(baseURL)/top/\(limit)/podcasts.json")!
        fetchChart(url: url, completion: completion)
    }

    func fetchFeaturedPodcasts(limit: Int = 20, completion: @escaping ([PodcastSearchResult]) -> Void) {
        // Fetch from top charts but take a different slice (positions 1-20)
        let url = URL(string: "\(baseURL)/top/50/podcasts.json")!
        fetchChart(url: url) { results in
            // Take the first 20 for featured
            let featuredResults = Array(results.prefix(limit))
            completion(featuredResults)
        }
    }

    func fetchTrendingEpisodes(limit: Int = 10, completion: @escaping ([TrendingEpisode]) -> Void) {
        // Use a different range from the top charts to get variety
        let url = URL(string: "\(baseURL)/top/50/podcasts.json")!
        NetworkManager.shared.fetchData(with: URLRequest(url: url)) { result in
            guard case let .success(data) = result else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            guard let response = try? JSONDecoder().decode(AppleTopChartResponse.self, from: data) else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            // Take a different slice (positions 21-30) to avoid overlap with featured
            let startIndex = 20 // Skip first 20 used by featured
            let endIndex = min(startIndex + limit, response.feed.results.count)
            let selectedResults = Array(response.feed.results[startIndex..<endIndex])
            
            let episodes = selectedResults.enumerated().compactMap { index, result -> TrendingEpisode? in
                guard let id = Int(result.id) else { return nil }
                
                // Create proper artwork URL with fallback
                let artworkURL = self.createArtworkURL(from: result.artworkUrl100)
                
                // Create proper feed URL - try to get actual RSS feed
                let feedURL = URL(string: "https://podcasts.apple.com/podcast/id\(id)") ?? URL(string: "https://example.com")!
                
                return TrendingEpisode(
                    id: id,
                    title: "Latest Episode", // Generic title since we don't have episode-specific data
                    podcastName: result.name,
                    feedURL: feedURL,
                    artworkURL: artworkURL
                )
            }
            
            DispatchQueue.main.async {
                completion(Array(episodes))
            }
        }
    }

    // MARK: - Public API (Async/Await)
    
    func fetchTrendingEpisodes(limit: Int = 10) async -> [TrendingEpisode] {
        return await withCheckedContinuation { continuation in
            fetchTrendingEpisodes(limit: limit) { episodes in
                continuation.resume(returning: episodes)
            }
        }
    }
    
    func fetchFeaturedPodcasts(limit: Int = 20) async -> [PodcastSearchResult] {
        return await withCheckedContinuation { continuation in
            fetchFeaturedPodcasts(limit: limit) { podcasts in
                continuation.resume(returning: podcasts)
            }
        }
    }
    
    func fetchTopCharts(limit: Int = 100) async -> [PodcastSearchResult] {
        return await withCheckedContinuation { continuation in
            fetchTopCharts(limit: limit) { podcasts in
                continuation.resume(returning: podcasts)
            }
        }
    }

    // MARK: - Helpers
    
    private func createArtworkURL(from artworkString: String?) -> URL? {
        guard let artworkString = artworkString, !artworkString.isEmpty else { return nil }
        
        // Try to upgrade to higher resolution if possible
        let highResArtwork = artworkString
            .replacingOccurrences(of: "100x100", with: "600x600")
            .replacingOccurrences(of: "/100/", with: "/600/")
        
        return URL(string: highResArtwork) ?? URL(string: artworkString)
    }
    
    private func fetchChart(url: URL, completion: @escaping ([PodcastSearchResult]) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        NetworkManager.shared.fetchData(with: request) { result in
            guard case let .success(data) = result else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            guard let response = try? JSONDecoder().decode(AppleTopChartResponse.self, from: data) else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let ids = response.feed.results.compactMap { Int($0.id) }
            self.lookupPodcasts(ids: ids, completion: completion)
        }
    }

    private func lookupPodcasts(ids: [Int], completion: @escaping ([PodcastSearchResult]) -> Void) {
        guard !ids.isEmpty else { 
            DispatchQueue.main.async { completion([]) }
            return 
        }
        
        let idString = ids.map(String.init).joined(separator: ",")
        let urlString = "https://itunes.apple.com/lookup?id=\(idString)&entity=podcast"
        guard let url = URL(string: urlString) else { 
            DispatchQueue.main.async { completion([]) }
            return 
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        NetworkManager.shared.fetchData(with: request) { result in
            guard case let .success(data) = result else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            guard let response = try? JSONDecoder().decode(iTunesSearchResponse.self, from: data) else {
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
            
            DispatchQueue.main.async { completion(results) }
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
            if let url = URL(string: artworkString), !artworkString.isEmpty {
                return url
            }
        }
        
        return nil
    }

    private func fetchLatestEpisode(for podcastId: Int, completion: @escaping (TrendingEpisode?) -> Void) {
        iTunesSearchService.shared.getPodcastDetails(iTunesId: podcastId) { result in
            guard let podcast = result else {
                completion(nil)
                return
            }
            
            // Create a trending episode from the podcast info
            let episode = TrendingEpisode(
                id: podcastId,
                title: "Latest Episode",
                podcastName: podcast.title,
                feedURL: podcast.feedURL,
                artworkURL: podcast.artworkURL
            )
            completion(episode)
        }
    }
}

// MARK: - Apple Top Chart Response Models

struct AppleTopChartResponse: Codable {
    let feed: AppleTopChartFeed
}

struct AppleTopChartFeed: Codable {
    let results: [AppleTopChartResult]
}

struct AppleTopChartResult: Codable {
    let id: String
    let name: String
    let artistName: String
    let artworkUrl100: String?
}
