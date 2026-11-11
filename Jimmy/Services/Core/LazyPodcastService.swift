import Foundation
import os.log

/// Lazy wrapper for PodcastService to defer initialization
/// This prevents podcast service from loading during app startup
final class LazyPodcastService {
    static let shared = LazyPodcastService()
    
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "LazyPodcastService")
    private var _podcastService: PodcastService?
    
    private init() {
        logger.info("LazyPodcastService initialized - deferring PodcastService loading")
    }
    
    /// Get the podcast service, loading it lazily if needed
    private var podcastService: PodcastService? {
        if let service = _podcastService {
            return service
        }
        
        logger.info("Loading PodcastService on-demand")
        guard let service = PodcastService.shared else {
            logger.error("PodcastService.shared is nil - DIContainer may not be initialized")
            return nil
        }
        _podcastService = service
        return service
    }
    
    /// Add podcast from URL (used in URL handling)
    func addPodcast(from url: URL) async throws -> (Podcast, [Episode]) {
        guard let service = podcastService else {
            throw LazyServiceError.serviceUnavailable("PodcastService not available")
        }
        return try await service.addPodcast(from: url)
    }
}

/// Errors for lazy service loading
enum LazyServiceError: Error, LocalizedError {
    case serviceUnavailable(String)
    
    var errorDescription: String? {
        switch self {
        case .serviceUnavailable(let message):
            return "Service unavailable: \(message)"
        }
    }
}