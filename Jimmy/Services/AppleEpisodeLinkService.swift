import Foundation

class AppleEpisodeLinkService {
    static let shared = AppleEpisodeLinkService()
    private init() {}

    /// Fetch the Apple Podcasts URL for a specific episode by querying the iTunes Search API.
    /// - Parameters:
    ///   - episode: Episode object to search for.
    ///   - podcast: Podcast the episode belongs to.
    ///   - completion: Callback with optional URL.
    func fetchAppleLink(for episode: Episode, podcast: Podcast, completion: @escaping (URL?) -> Void) {
        iTunesSearchService.shared.searchPodcasts(query: podcast.title) { results in
            let lowerTitle = podcast.title.lowercased()
            let lowerAuthor = podcast.author.lowercased()
            guard let match = results.first(where: { res in
                res.title.lowercased().contains(lowerTitle) || lowerTitle.contains(res.title.lowercased()) ||
                res.author.lowercased().contains(lowerAuthor) || lowerAuthor.contains(res.author.lowercased())
            }) else {
                completion(nil)
                return
            }

            iTunesSearchService.shared.searchEpisode(podcastId: match.id, episodeTitle: episode.title) { episodeResult in
                if let urlString = episodeResult?.trackViewUrl, let url = URL(string: urlString) {
                    completion(url)
                } else {
                    completion(nil)
                }
            }
        }
    }
}
