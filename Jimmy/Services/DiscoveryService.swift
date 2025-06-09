import Foundation

struct TrendingEpisode: Identifiable {
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
        let url = URL(string: "\(baseURL)/top/\(limit)/podcasts.json")!
        fetchChart(url: url, completion: completion)
    }

    func fetchTrendingEpisodes(limit: Int = 10, completion: @escaping ([TrendingEpisode]) -> Void) {
        let url = URL(string: "\(baseURL)/top/\(limit)/podcasts.json")!
        NetworkManager.shared.fetchData(with: URLRequest(url: url)) { result in
            guard case let .success(data) = result else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            guard let response = try? JSONDecoder().decode(AppleTopChartResponse.self, from: data) else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let ids = response.feed.results.compactMap { Int($0.id) }
            let group = DispatchGroup()
            var episodes: [TrendingEpisode] = []
            for id in ids {
                group.enter()
                self.fetchLatestEpisode(for: id) { episode in
                    if let episode = episode { episodes.append(episode) }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                completion(episodes)
            }
        }
    }

    // MARK: - Helpers
    private func fetchChart(url: URL, completion: @escaping ([PodcastSearchResult]) -> Void) {
        NetworkManager.shared.fetchData(with: URLRequest(url: url)) { result in
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
        guard !ids.isEmpty else { completion([]); return }
        let idString = ids.map(String.init).joined(separator: ",")
        let urlString = "https://itunes.apple.com/lookup?id=\(idString)&entity=podcast"
        guard let url = URL(string: urlString) else { completion([]); return }
        NetworkManager.shared.fetchData(with: URLRequest(url: url)) { result in
            guard case let .success(data) = result,
                  let lookup = try? JSONDecoder().decode(iTunesSearchResponse.self, from: data) else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let results = lookup.results.compactMap { item -> PodcastSearchResult? in
                guard let feedUrlStr = item.feedUrl,
                      let feedURL = URL(string: feedUrlStr) else { return nil }
                return PodcastSearchResult(
                    id: item.collectionId,
                    title: item.collectionName,
                    author: item.artistName,
                    feedURL: feedURL,
                    artworkURL: URL(string: item.artworkUrl600 ?? item.artworkUrl100 ?? ""),
                    description: item.description,
                    genre: item.primaryGenreName,
                    trackCount: item.trackCount
                )
            }
            DispatchQueue.main.async { completion(results) }
        }
    }

    private func fetchLatestEpisode(for podcastId: Int, completion: @escaping (TrendingEpisode?) -> Void) {
        let urlString = "https://itunes.apple.com/lookup?id=\(podcastId)&entity=podcastEpisode&limit=1"
        guard let url = URL(string: urlString) else { completion(nil); return }
        NetworkManager.shared.fetchData(with: URLRequest(url: url)) { result in
            guard case let .success(data) = result,
                  let lookup = try? JSONDecoder().decode(iTunesEpisodeLookupResponse.self, from: data),
                  lookup.results.count > 1 else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let podcast = lookup.results[0]
            let episode = lookup.results[1]
            guard let feedUrl = podcast.feedUrl, let feedURL = URL(string: feedUrl) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let episodeItem = TrendingEpisode(
                id: episode.trackId,
                title: episode.trackName,
                podcastName: podcast.collectionName,
                feedURL: feedURL,
                artworkURL: URL(string: episode.artworkUrl600 ?? episode.artworkUrl100 ?? podcast.artworkUrl600 ?? podcast.artworkUrl100 ?? "")
            )
            DispatchQueue.main.async { completion(episodeItem) }
        }
    }
}

private struct AppleTopChartResponse: Codable {
    let feed: AppleFeed
}

private struct AppleFeed: Codable {
    let results: [ApplePodcastChartItem]
}

private struct ApplePodcastChartItem: Codable {
    let id: String
}

private struct iTunesEpisodeLookupResponse: Codable {
    let results: [iTunesEpisodeLookupItem]
}

private struct iTunesEpisodeLookupItem: Codable {
    let collectionName: String
    let trackId: Int
    let trackName: String
    let feedUrl: String?
    let artworkUrl100: String?
    let artworkUrl600: String?
}
