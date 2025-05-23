import Foundation

struct iTunesSearchService {
    static let shared = iTunesSearchService()
    
    private init() {}
    
    // Search for podcasts using iTunes Search API
    func searchPodcasts(query: String, completion: @escaping ([PodcastSearchResult]) -> Void) {
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
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }
            
            do {
                let searchResponse = try JSONDecoder().decode(iTunesSearchResponse.self, from: data)
                let podcastResults = searchResponse.results.compactMap { result -> PodcastSearchResult? in
                    guard let feedUrl = URL(string: result.feedUrl ?? "") else { return nil }
                    
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
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }.resume()
    }
    
    // Get podcast details by iTunes ID
    func getPodcastDetails(iTunesId: Int, completion: @escaping (PodcastSearchResult?) -> Void) {
        let urlString = "https://itunes.apple.com/lookup?id=\(iTunesId)&entity=podcast"
        
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    completion(nil)
                }
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
        }.resume()
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
        return Podcast(
            title: title,
            author: author,
            feedURL: feedURL,
            artworkURL: artworkURL
        )
    }
} 