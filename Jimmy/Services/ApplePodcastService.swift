import Foundation
import MediaPlayer
import StoreKit

class ApplePodcastService {
    static let shared = ApplePodcastService()
    
    private init() {}
    
    // MARK: - Main Import Methods
    
    /// Import all subscriptions from Apple Podcasts using multiple methods
    func importAllApplePodcastSubscriptions(completion: @escaping ([Podcast], Error?) -> Void) {
        // Try comprehensive approach: guide user through manual export + existing methods
        requestComprehensiveImport(completion: completion)
    }
    
    /// Comprehensive import that combines multiple methods
    private func requestComprehensiveImport(completion: @escaping ([Podcast], Error?) -> Void) {
        var allPodcasts: [Podcast] = []
        let group = DispatchGroup()
        
        // Method 1: Try the original MPMediaLibrary approach (for downloaded content)
        group.enter()
        importApplePodcastSubscriptions { podcasts, error in
            if !podcasts.isEmpty {
                allPodcasts.append(contentsOf: podcasts)
                #if DEBUG
                print("📱 Method 1 (MPMediaLibrary): Found \(podcasts.count) podcasts")
                #endif
            }
            group.leave()
        }
        
        // Method 2: Try to access recently played content (iOS 14+)
        group.enter()
        importFromRecentActivity { podcasts, error in
            if let podcasts = podcasts, !podcasts.isEmpty {
                // Remove duplicates
                let existingURLs = Set(allPodcasts.map { $0.feedURL.absoluteString })
                let newPodcasts = podcasts.filter { !existingURLs.contains($0.feedURL.absoluteString) }
                allPodcasts.append(contentsOf: newPodcasts)
                #if DEBUG
                print("📱 Method 2 (Recent Activity): Found \(newPodcasts.count) new podcasts")
                #endif
            }
            group.leave()
        }
        
        // Method 3: Try iCloud Podcasts data (if accessible)
        group.enter()
        importFromiCloudData { podcasts, error in
            if let podcasts = podcasts, !podcasts.isEmpty {
                // Remove duplicates
                let existingURLs = Set(allPodcasts.map { $0.feedURL.absoluteString })
                let newPodcasts = podcasts.filter { !existingURLs.contains($0.feedURL.absoluteString) }
                allPodcasts.append(contentsOf: newPodcasts)
                #if DEBUG
                print("📱 Method 3 (iCloud Data): Found \(newPodcasts.count) new podcasts")
                #endif
            }
            group.leave()
        }
        
        group.notify(queue: .main) {
            if allPodcasts.isEmpty {
                // If no podcasts found, show guided import instructions
                completion([], ApplePodcastError.noItemsFoundUseManualMethod)
            } else {
                #if DEBUG
                print("📱 Total unique podcasts found: \(allPodcasts.count)")
                #endif
                completion(allPodcasts, nil)
            }
        }
    }
    
    // MARK: - Enhanced Import Methods
    
    /// Import from recent media activity (iOS 14+)
    private func importFromRecentActivity(completion: @escaping ([Podcast]?, Error?) -> Void) {
        // Access recently played media items
        let recentQuery = MPMediaQuery()
        
        // Try to get all media items sorted by last played date
        if let allItems = recentQuery.items {
            let podcastItems = allItems.filter { item in
                item.mediaType == .podcast &&
                item.lastPlayedDate != nil
            }.sorted { item1, item2 in
                guard let date1 = item1.lastPlayedDate,
                      let date2 = item2.lastPlayedDate else { return false }
                return date1 > date2
            }
            
            processPodcastItems(podcastItems, method: "Recent Activity", completion: completion)
        } else {
            completion(nil, ApplePodcastError.noItemsFound)
        }
    }
    
    /// Try to access iCloud synced podcast data
    private func importFromiCloudData(completion: @escaping ([Podcast]?, Error?) -> Void) {
        // For now, skip iCloud data access to avoid entitlement issues
        // This method could be enhanced in the future with proper iCloud setup
        
        #if DEBUG
        print("📱 Method 3 (iCloud Data): Skipping iCloud access (requires entitlements)")
        #endif
        
        // Return empty result without error - this is expected for most users
        completion([], nil)
        
        // NOTE: To properly implement iCloud access, you would need:
        // 1. Add iCloud entitlements to the app
        // 2. Configure CloudKit container
        // 3. Add proper error handling for iCloud unavailability
        
        /* Future implementation might look like:
        
        // Check if iCloud is available and configured
        guard FileManager.default.ubiquityIdentityToken != nil else {
            #if DEBUG
            print("📱 iCloud not available or not signed in")
            #endif
            completion([], nil)
            return
        }
        
        // Only attempt iCloud access if properly configured
        DispatchQueue.global(qos: .background).async {
            // Safe iCloud access code here
            DispatchQueue.main.async {
                completion([], nil)
            }
        }
        */
    }
    
    /// Enhanced processing with better podcast detection
    private func processPodcastItems(_ items: [MPMediaItem], method: String, completion: @escaping ([Podcast]?, Error?) -> Void) {
        guard !items.isEmpty else {
            completion(nil, ApplePodcastError.noItemsFound)
            return
        }
        
        // Group by podcast series with enhanced logic
        var podcastsDict: [String: (item: MPMediaItem, episodes: Int)] = [:]
        
        for item in items {
            var podcastTitle: String?
            var artist: String?
            
            // Enhanced podcast identification
            if let title = item.podcastTitle, !title.isEmpty {
                podcastTitle = title
            } else if let album = item.albumTitle, !album.isEmpty {
                podcastTitle = album
            } else if let title = item.title, !title.isEmpty {
                // Use the raw title without parsing
                podcastTitle = title
            }
            
            if let itemArtist = item.artist, !itemArtist.isEmpty {
                artist = itemArtist
            } else if let albumArtist = item.albumArtist, !albumArtist.isEmpty {
                artist = albumArtist
            }
            
            if let podcastTitle = podcastTitle, let artist = artist {
                let key = "\(podcastTitle)-\(artist)".lowercased()
                if let existing = podcastsDict[key] {
                    // Update with more recent item if this one is newer
                    if let newDate = item.lastPlayedDate, let existingDate = existing.item.lastPlayedDate {
                        if newDate > existingDate {
                            podcastsDict[key] = (item: item, episodes: existing.episodes + 1)
                        } else {
                            podcastsDict[key] = (item: existing.item, episodes: existing.episodes + 1)
                        }
                    } else {
                        podcastsDict[key] = (item: existing.item, episodes: existing.episodes + 1)
                    }
                } else {
                    podcastsDict[key] = (item: item, episodes: 1)
                }
                
                #if DEBUG
                print("✅ [\(method)] Added: \(podcastTitle) by \(artist) (\(podcastsDict[key]!.episodes) episodes)")
                #endif
            }
        }
        
        guard !podcastsDict.isEmpty else {
            completion(nil, ApplePodcastError.noItemsFound)
            return
        }
        
        // Convert to Podcast objects
        var podcasts: [Podcast] = []
        let group = DispatchGroup()
        
        for (_, data) in podcastsDict {
            group.enter()
            
            let mediaItem = data.item
            var podcastTitle: String = ""
            var artist: String = ""
            
            if let title = mediaItem.podcastTitle ?? mediaItem.albumTitle ?? mediaItem.title {
                podcastTitle = title
            }
            if let itemArtist = mediaItem.artist ?? mediaItem.albumArtist {
                artist = itemArtist
            }
            
            // Search for RSS feed
            findRSSFeedURL(podcastTitle: podcastTitle, artist: artist) { feedURL in
                defer { group.leave() }
                
                if let feedURL = feedURL {
                    let podcast = Podcast(
                        title: podcastTitle,
                        author: artist,
                        description: "",
                        feedURL: feedURL,
                        artworkURL: self.getArtworkURL(from: mediaItem)
                    )
                    podcasts.append(podcast)
                    
                    #if DEBUG
                    print("✅ [\(method)] Found RSS feed for: \(podcastTitle)")
                    #endif
                }
            }
        }
        
        group.notify(queue: .main) {
            completion(podcasts, nil)
        }
    }
    
    // MARK: - Original Method (for backward compatibility)
    
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
        // Try multiple query approaches to get more comprehensive results
        var allItems: [MPMediaItem] = []
        
        // Method 1: Standard podcast query
        let podcastQuery = MPMediaQuery.podcasts()
        if let items = podcastQuery.items {
            allItems.append(contentsOf: items)
            #if DEBUG
            print("📱 Method 1 - Standard podcast query found: \(items.count) items")
            #endif
        }
        
        // Method 2: Query all items and filter for podcasts
        let allQuery = MPMediaQuery()
        if let items = allQuery.items {
            let podcastItems = items.filter { item in
                item.mediaType == .podcast
            }
            allItems.append(contentsOf: podcastItems)
            #if DEBUG
            print("📱 Method 2 - All items filtered for podcasts found: \(podcastItems.count) items")
            #endif
        }
        
        // Method 3: Try to get podcast items by media type
        let mediaTypeQuery = MPMediaQuery()
        let mediaTypePredicate = MPMediaPropertyPredicate(value: MPMediaType.podcast.rawValue, forProperty: MPMediaItemPropertyMediaType)
        mediaTypeQuery.addFilterPredicate(mediaTypePredicate)
        if let items = mediaTypeQuery.items {
            allItems.append(contentsOf: items)
            #if DEBUG
            print("📱 Method 3 - Media type query found: \(items.count) items")
            #endif
        }
        
        // Remove duplicates by persistent ID
        var uniqueItems: [MPMediaItem] = []
        var seenIDs: Set<MPMediaEntityPersistentID> = []
        
        for item in allItems {
            if !seenIDs.contains(item.persistentID) {
                seenIDs.insert(item.persistentID)
                uniqueItems.append(item)
            }
        }
        
        #if DEBUG
        print("📱 Total unique items after combining methods: \(uniqueItems.count)")
        #endif
        
        processPodcastItems(uniqueItems, method: "MPMediaLibrary") { podcasts, error in
            completion(podcasts ?? [], error)
        }
    }
    
    private func findRSSFeedURL(podcastTitle: String, artist: String, completion: @escaping (URL?) -> Void) {
        // Try multiple search strategies
        searchWithFallback(podcastTitle: podcastTitle, artist: artist, attempt: 0, completion: completion)
    }
    
    private func searchWithFallback(podcastTitle: String, artist: String, attempt: Int, completion: @escaping (URL?) -> Void) {
        // Different search query strategies
        let sanitizedTitle = sanitizeSearchQuery(podcastTitle)
        let sanitizedArtist = sanitizeSearchQuery(artist)
        
        let searchQueries = [
            "\(sanitizedTitle) \(sanitizedArtist)",           // Original: full title + artist
            sanitizedTitle,                                   // Title only
            "\(sanitizedTitle) podcast",                      // Title + "podcast"
            "\"\(sanitizedTitle)\" \(sanitizedArtist)",       // Quoted title + artist
            sanitizedArtist.isEmpty ? sanitizedTitle : "\(sanitizedArtist) \(sanitizedTitle)" // Artist first
        ]
        
        guard attempt < searchQueries.count else {
            completion(nil)
            return
        }
        
        let currentQuery = searchQueries[attempt]
        
        // Add timeout for search requests
        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
            completion(nil)
        }
        
        iTunesSearchService.shared.searchPodcasts(query: currentQuery) { results in
            timeoutTimer.invalidate()
            
            guard !results.isEmpty else {
                // Try next search strategy
                self.searchWithFallback(podcastTitle: podcastTitle, artist: artist, attempt: attempt + 1, completion: completion)
                return
            }
            
            let lowercasedPodcastTitle = podcastTitle.lowercased()
            let lowercasedArtist = artist.lowercased()
            let normalizedPodcastTitle = self.normalizeText(podcastTitle)
            let normalizedArtist = self.normalizeText(artist)
            
            // Strategy 1: Exact match on both title and artist
            let exactMatch = results.first { result in
                result.title.lowercased() == lowercasedPodcastTitle &&
                result.author.lowercased() == lowercasedArtist
            }
            
            // Strategy 2: Exact title match
            let titleExactMatch = results.first { result in
                result.title.lowercased() == lowercasedPodcastTitle
            }
            
            // Strategy 3: Normalized exact match
            let normalizedExactMatch = results.first { result in
                self.normalizeText(result.title) == normalizedPodcastTitle &&
                self.normalizeText(result.author) == normalizedArtist
            }
            
            // Strategy 4: Title normalized exact match
            let titleNormalizedMatch = results.first { result in
                self.normalizeText(result.title) == normalizedPodcastTitle
            }
            
            // Strategy 5: Partial title and artist matching
            let partialMatch = results.first { result in
                let resultTitle = result.title.lowercased()
                let resultArtist = result.author.lowercased()
                
                return (resultTitle.contains(lowercasedPodcastTitle) ||
                        lowercasedPodcastTitle.contains(resultTitle)) &&
                       (resultArtist.contains(lowercasedArtist) ||
                        lowercasedArtist.contains(resultArtist))
            }
            
            // Strategy 6: Fuzzy title matching with normalized text
            let fuzzyMatch = results.first { result in
                let normalizedResultTitle = self.normalizeText(result.title)
                return normalizedResultTitle.contains(normalizedPodcastTitle) ||
                       normalizedPodcastTitle.contains(normalizedResultTitle)
            }
            
            // Strategy 7: Artist-focused matching (for cases where title might be very different)
            let artistMatch = results.first { result in
                let normalizedResultArtist = self.normalizeText(result.author)
                return normalizedResultArtist == normalizedArtist &&
                       !normalizedResultArtist.isEmpty
            }
            
            // Choose the best match with priority order
            let bestMatch = exactMatch ?? 
                           titleExactMatch ?? 
                           normalizedExactMatch ?? 
                           titleNormalizedMatch ?? 
                           partialMatch ?? 
                           fuzzyMatch ?? 
                           artistMatch
            
            // If we found a good match, use it
            if let match = bestMatch {
                completion(match.feedURL)
                return
            }
            
            // If no good match found and we have more search strategies, try the next one
            if attempt < searchQueries.count - 1 {
                self.searchWithFallback(podcastTitle: podcastTitle, artist: artist, attempt: attempt + 1, completion: completion)
            } else {
                // Last resort: use first result if available
                completion(results.first?.feedURL)
                
                // Debug logging for failed matches (in development)
                #if DEBUG
                if results.isEmpty {
                    print("⚠️ No search results for podcast: '\(podcastTitle)' by '\(artist)'")
                } else {
                    print("⚠️ Failed to match podcast: '\(podcastTitle)' by '\(artist)'")
                    print("Final search results:")
                    for (index, result) in results.prefix(3).enumerated() {
                        print("  \(index + 1). '\(result.title)' by '\(result.author)'")
                    }
                }
                #endif
            }
        }
    }
    
    private func normalizeText(_ text: String) -> String {
        return text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: #"[^\w\s]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func sanitizeSearchQuery(_ text: String) -> String {
        return text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }
    
    private func getArtworkURL(from mediaItem: MPMediaItem) -> URL? {
        // Try to get the largest available artwork
        if mediaItem.artwork != nil {
            // The MediaPlayer framework doesn't directly provide URLs
            // We'll rely on the iTunes search to provide artwork URLs
            return nil
        }
        return nil
    }
    
    // MARK: - Manual Import Guidance
    
    /// Get step-by-step instructions for manual export from Apple Podcasts
    static func getManualImportInstructions() -> [String] {
        return [
            "📱 Open the Apple Podcasts app on your iPhone/iPad",
            "🏠 Tap 'Library' at the bottom",
            "📺 Tap 'Shows' to see all your subscriptions",
            "📱 Take screenshots of your podcast list (scroll to capture all)",
            "💡 Or manually note down your favorite podcast names",
            "🔄 Return to Jimmy and use 'Manual Import' to add them by name",
            "🌐 You can also share podcast URLs from Apple Podcasts directly to Jimmy",
            "",
            "💡 Pro Tip: In Apple Podcasts, tap share on any podcast and copy the link, then paste it into Jimmy's Manual Import!"
        ]
    }
}

// MARK: - Error Types

enum ApplePodcastError: LocalizedError {
    case accessDenied
    case authorizationNotDetermined
    case noItemsFound
    case noItemsFoundUseManualMethod
    case sharedContainerNotAccessible
    case databaseNotFound
    case notImplemented
    case iCloudDataNotAccessible
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access to media library was denied. Please enable access in Settings > Privacy & Security > Media & Apple Music."
        case .authorizationNotDetermined:
            return "Media library access authorization not determined."
        case .noItemsFound:
            return "No podcast episodes found in your device's media library. This import only finds podcasts with downloaded episodes."
        case .noItemsFoundUseManualMethod:
            return "Unable to automatically detect your Apple Podcasts subscriptions. This is a limitation of iOS - Apple Podcasts only exposes downloaded episodes to other apps, not your full subscription list. Please use the Manual Import method below to add your podcasts!"
        case .sharedContainerNotAccessible:
            return "Cannot access Apple Podcasts shared data."
        case .databaseNotFound:
            return "Apple Podcasts database not found."
        case .notImplemented:
            return "This import method is not yet implemented."
        case .iCloudDataNotAccessible:
            return "Cannot access iCloud podcast data."
        case .unknown:
            return "An unknown error occurred while importing subscriptions."
        }
    }
} 