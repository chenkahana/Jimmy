import Foundation
import MediaPlayer

class ApplePodcastService {
    static let shared = ApplePodcastService()
    
    private init() {}
    
    // Import subscriptions from Apple Podcasts using Media Player framework
    func importApplePodcastSubscriptions(completion: @escaping ([Podcast], Error?) -> Void) {
        // Request authorization to access media library
        MPMediaLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self.fetchPodcastSubscriptions(completion: completion)
                case .denied, .restricted:
                    completion([], ApplePodcastError.accessDenied)
                case .notDetermined:
                    completion([], ApplePodcastError.authorizationNotDetermined)
                @unknown default:
                    completion([], ApplePodcastError.unknown)
                }
            }
        }
    }
    
    private func fetchPodcastSubscriptions(completion: @escaping ([Podcast], Error?) -> Void) {
        // Query for podcast items in the user's library
        let query = MPMediaQuery.podcasts()
        
        guard let items = query.items else {
            completion([], ApplePodcastError.noItemsFound)
            return
        }
        
        // Group by podcast series
        var podcastsDict: [String: MPMediaItem] = [:]
        
        for item in items {
            if let podcastTitle = item.podcastTitle,
               let artist = item.artist {
                let key = "\(podcastTitle)-\(artist)"
                if podcastsDict[key] == nil {
                    podcastsDict[key] = item
                }
            }
        }
        
        var podcasts: [Podcast] = []
        let group = DispatchGroup()
        
        for (_, mediaItem) in podcastsDict {
            group.enter()
            
            if let podcastTitle = mediaItem.podcastTitle,
               let artist = mediaItem.artist {
                
                // Try to find RSS feed URL using iTunes Search API
                self.findRSSFeedURL(podcastTitle: podcastTitle, artist: artist) { feedURL in
                    defer { group.leave() }
                    
                    if let feedURL = feedURL {
                        let podcast = Podcast(
                            title: podcastTitle,
                            author: artist,
                            feedURL: feedURL,
                            artworkURL: self.getArtworkURL(from: mediaItem)
                        )
                        podcasts.append(podcast)
                    }
                }
            } else {
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(podcasts, nil)
        }
    }
    
    private func findRSSFeedURL(podcastTitle: String, artist: String, completion: @escaping (URL?) -> Void) {
        // Use iTunes Search API to find the RSS feed URL
        let searchQuery = "\(podcastTitle) \(artist)"
        
        iTunesSearchService.shared.searchPodcasts(query: searchQuery) { results in
            // Find best match based on title and artist similarity
            let bestMatch = results.first { result in
                result.title.lowercased() == podcastTitle.lowercased() &&
                result.author.lowercased() == artist.lowercased()
            } ?? results.first { result in
                result.title.lowercased().contains(podcastTitle.lowercased()) ||
                podcastTitle.lowercased().contains(result.title.lowercased())
            }
            
            completion(bestMatch?.feedURL)
        }
    }
    
    private func getArtworkURL(from mediaItem: MPMediaItem) -> URL? {
        // Try to get the largest available artwork
        if let artwork = mediaItem.artwork {
            // The MediaPlayer framework doesn't directly provide URLs
            // We'll rely on the iTunes search to provide artwork URLs
            return nil
        }
        return nil
    }
    
    // Alternative method: Try to access Apple Podcasts database directly (iOS 14+)
    func importFromApplePodcastsDatabase(completion: @escaping ([Podcast], Error?) -> Void) {
        // This method attempts to read from Apple Podcasts' shared container
        // Note: This may require specific entitlements and may not work in all cases
        
        guard let sharedContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.apple.podcasts"
        ) else {
            completion([], ApplePodcastError.sharedContainerNotAccessible)
            return
        }
        
        let databasePath = sharedContainer.appendingPathComponent("Documents/MTLibrary.sqlite")
        
        // Check if database exists
        guard FileManager.default.fileExists(atPath: databasePath.path) else {
            completion([], ApplePodcastError.databaseNotFound)
            return
        }
        
        // For security and complexity reasons, we'll use the Media Player approach instead
        // This is left as a placeholder for future implementation if needed
        completion([], ApplePodcastError.notImplemented)
    }
}

// MARK: - Error Types

enum ApplePodcastError: LocalizedError {
    case accessDenied
    case authorizationNotDetermined
    case noItemsFound
    case sharedContainerNotAccessible
    case databaseNotFound
    case notImplemented
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access to media library was denied. Please enable access in Settings > Privacy & Security > Media & Apple Music."
        case .authorizationNotDetermined:
            return "Media library access authorization not determined."
        case .noItemsFound:
            return "No podcast subscriptions found in Apple Podcasts."
        case .sharedContainerNotAccessible:
            return "Cannot access Apple Podcasts shared data."
        case .databaseNotFound:
            return "Apple Podcasts database not found."
        case .notImplemented:
            return "This import method is not yet implemented."
        case .unknown:
            return "An unknown error occurred while importing subscriptions."
        }
    }
} 