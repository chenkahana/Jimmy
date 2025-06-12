import Foundation

// MARK: - Concrete Search Repository

/// iTunes search repository implementation
final class ConcreteiTunesSearchRepository: SearchRepositoryProtocol {
    private let searchService = iTunesSearchService.shared
    
    func searchPodcasts(query: String) async throws -> [Podcast] {
        return await withCheckedContinuation { continuation in
            searchService.searchPodcasts(query: query) { results in
                let podcasts = results.map { $0.toPodcast() }
                continuation.resume(returning: podcasts)
            }
        }
    }
}

// MARK: - Search Repository Error

enum SearchRepositoryError: LocalizedError {
    case networkUnavailable
    case invalidURL
    case parsingError
    
    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Network connection unavailable"
        case .invalidURL:
            return "Invalid search URL"
        case .parsingError:
            return "Failed to parse search results"
        }
    }
} 