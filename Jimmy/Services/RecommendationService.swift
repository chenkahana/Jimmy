import Foundation

class RecommendationService {
    static let shared = RecommendationService()
    private init() {}

    /// Fetch recommended podcasts based on current subscriptions using the iTunes Search API.
    /// - Parameters:
    ///   - podcasts: Subscribed podcasts to base recommendations on.
    ///   - completion: Callback with array of search results.
    func getRecommendations(basedOn podcasts: [Podcast], completion: @escaping ([PodcastSearchResult]) -> Void) {
        guard !podcasts.isEmpty else {
            completion([])
            return
        }

        let subscribedFeeds = Set(podcasts.map { $0.feedURL })
        var aggregated: [PodcastSearchResult] = []
        let group = DispatchGroup()

        // Limit to avoid excessive requests
        for podcast in podcasts.prefix(5) {
            group.enter()
            let query = podcast.author
            iTunesSearchService.shared.searchPodcasts(query: query) { results in
                let filtered = results.filter { !subscribedFeeds.contains($0.feedURL) }
                aggregated.append(contentsOf: filtered)
                group.leave()
            }
        }

        group.notify(queue: .main) {
            var seen: Set<URL> = []
            let unique = aggregated.filter { result in
                if seen.contains(result.feedURL) { return false }
                seen.insert(result.feedURL)
                return true
            }
            completion(Array(unique.prefix(50)))
        }
    }
}
