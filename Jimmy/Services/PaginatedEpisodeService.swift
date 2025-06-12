import Foundation
import OSLog

/// A value type that represents a single page of episodes from a paginated request.
struct EpisodePage {
    let episodes: [Episode]
    let nextCursor: String?
    
    var hasMorePages: Bool { nextCursor != nil }
}

/// Service responsible for fetching episodes with pagination support.
/// Combines caching and network operations for optimal performance.
final class PaginatedEpisodeService {
    static let shared = PaginatedEpisodeService()
    
    private let logger = Logger(subsystem: "com.jimmy.app", category: "paginated-episodes")
    private let cacheService = EpisodeCacheService.shared
    private let networkManager = OptimizedNetworkManager.shared
    
    // Make initializer public so it can be used in ViewModels
    public init() {}
    
    // MARK: - Public API
    
    /// Fetches episodes for a podcast with cache-first strategy
    /// - Parameters:
    ///   - podcast: The podcast to fetch episodes for
    ///   - page: Page number (0-based)
    ///   - pageSize: Number of episodes per page
    /// - Returns: PaginationState with episodes and pagination info
    func fetchEpisodes(for podcast: Podcast, page: Int = 0, pageSize: Int = 20) async throws -> PaginationState {
        logger.info("Fetching episodes for podcast: \(podcast.title), page: \(page)")
        
        // Try cache first
        if let cachedEpisodes = await cacheService.getEpisodes(for: podcast.id) {
            logger.info("Found \(cachedEpisodes.count) cached episodes for \(podcast.title)")
            
            // Apply pagination to cached results
            let startIndex = page * pageSize
            let endIndex = min(startIndex + pageSize, cachedEpisodes.count)
            
            if startIndex < cachedEpisodes.count {
                let paginatedEpisodes = Array(cachedEpisodes[startIndex..<endIndex])
                return PaginationState(
                    episodes: paginatedEpisodes,
                    currentPage: page,
                    hasMorePages: endIndex < cachedEpisodes.count,
                    totalCount: cachedEpisodes.count,
                    isLoading: false
                )
            }
        }
        
        // Fetch from network if cache miss or requesting new page
        do {
            // Use the correct fetch API - fetch raw Data and parse as RSS
            let rssData = try await networkManager.fetchData(url: podcast.feedURL)
            let episodes = try parseRSSEpisodes(from: rssData, podcast: podcast)
            
            // Cache the episodes
            await cacheService.saveEpisodes(episodes, for: podcast.id)
            
            // Apply pagination
            let startIndex = page * pageSize
            let endIndex = min(startIndex + pageSize, episodes.count)
            let paginatedEpisodes = Array(episodes[startIndex..<endIndex])
            
            logger.info("Fetched and cached \(episodes.count) episodes for \(podcast.title)")
            
            return PaginationState(
                episodes: paginatedEpisodes,
                currentPage: page,
                hasMorePages: endIndex < episodes.count,
                totalCount: episodes.count,
                isLoading: false
            )
        } catch {
            logger.error("Failed to fetch episodes for \(podcast.title): \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Private Methods
    
    /// Simple RSS parser - placeholder implementation
    /// In a real app, you'd use a proper RSS parsing library
    private func parseRSSEpisodes(from data: Data, podcast: Podcast) throws -> [Episode] {
        // Parse RSS data to extract real episode information
        guard let rssString = String(data: data, encoding: .utf8),
              rssString.contains("<rss") || rssString.contains("<feed") else {
            throw NSError(domain: "RSSParseError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid RSS format"])
        }
        
        var episodes: [Episode] = []
        
        // Split by <item> tags to get individual episodes
        let itemComponents = rssString.components(separatedBy: "<item>")
        
        // Process all episodes - text data is minimal
        for index in 1..<itemComponents.count { // Skip the first component (before first <item>)
            autoreleasepool {
                let itemString = itemComponents[index]
                
                // Extract episode data from RSS item
                let title = extractValue(from: itemString, tag: "title") ?? "Episode \(index)"
                let description = extractValue(from: itemString, tag: "description")
                let audioURLString = extractAttribute(from: itemString, tag: "enclosure", attribute: "url")
                let pubDateString = extractValue(from: itemString, tag: "pubDate")
                let durationString = extractValue(from: itemString, tag: "itunes:duration")
                
                // Extract episode-specific artwork
                let episodeArtworkURL = extractEpisodeArtwork(from: itemString, fallbackURL: podcast.artworkURL)
                
                // Parse publication date
                let publishedDate = parsePubDate(pubDateString) ?? Date().addingTimeInterval(-Double(index) * 86400)
                
                // Parse duration
                let duration = parseDuration(durationString) ?? 3600 // Default 1 hour
                
                // Create episode with real data
                let episode = Episode(
                    id: UUID(),
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    artworkURL: episodeArtworkURL, // Use episode-specific artwork when available
                    audioURL: audioURLString.flatMap { URL(string: $0) },
                    description: description?.trimmingCharacters(in: .whitespacesAndNewlines),
                    played: false,
                    podcastID: podcast.id,
                    publishedDate: publishedDate,
                    localFileURL: nil,
                    playbackPosition: 0,
                    duration: duration
                )
                
                episodes.append(episode)
            }
        }
        
        // Sort episodes by publication date (newest first)
        episodes.sort { ($0.publishedDate ?? Date.distantPast) > ($1.publishedDate ?? Date.distantPast) }
        
        logger.info("📄 Parsed \(episodes.count) episodes from RSS feed")
        
        return episodes
    }
    
    // MARK: - RSS Parsing Helpers
    
    private func extractValue(from xmlString: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        
        let range = NSRange(location: 0, length: xmlString.count)
        guard let match = regex.firstMatch(in: xmlString, options: [], range: range) else { return nil }
        
        let matchRange = match.range(at: 1)
        guard let swiftRange = Range(matchRange, in: xmlString) else { return nil }
        
        let value = String(xmlString[swiftRange])
        return cleanHTMLTags(from: value)
    }
    
    private func extractAttribute(from xmlString: String, tag: String, attribute: String) -> String? {
        let pattern = "<\(tag)[^>]*\(attribute)=[\"']([^\"']*)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        
        let range = NSRange(location: 0, length: xmlString.count)
        guard let match = regex.firstMatch(in: xmlString, options: [], range: range) else { return nil }
        
        let matchRange = match.range(at: 1)
        guard let swiftRange = Range(matchRange, in: xmlString) else { return nil }
        
        return String(xmlString[swiftRange])
    }
    
    private func cleanHTMLTags(from string: String) -> String {
        let pattern = "<[^>]+>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return string }
        
        let range = NSRange(location: 0, length: string.count)
        let cleanString = regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: "")
        
        // Decode HTML entities
        return cleanString
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
    
    private func parsePubDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        
        let formatter = DateFormatter()
        
        // Try RFC 2822 format first (most common in RSS)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Try ISO 8601 format
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Try simple date format
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
    
    private func parseDuration(_ durationString: String?) -> TimeInterval? {
        guard let durationString = durationString else { return nil }
        
        // Handle HH:MM:SS format
        let components = durationString.components(separatedBy: ":")
        if components.count == 3,
           let hours = Double(components[0]),
           let minutes = Double(components[1]),
           let seconds = Double(components[2]) {
            return hours * 3600 + minutes * 60 + seconds
        }
        
        // Handle MM:SS format
        if components.count == 2,
           let minutes = Double(components[0]),
           let seconds = Double(components[1]) {
            return minutes * 60 + seconds
        }
        
        // Handle seconds only
        if let seconds = Double(durationString) {
            return seconds
        }
        
        return nil
    }
    
    private func extractEpisodeArtwork(from xmlString: String, fallbackURL: URL?) -> URL? {
        // Try multiple common episode artwork tags in order of preference
        
        // 1. iTunes episode image (most common)
        if let itunesImageURL = extractAttribute(from: xmlString, tag: "itunes:image", attribute: "href") {
            if let url = URL(string: itunesImageURL) {
                return url
            }
        }
        
        // 2. Media thumbnail (common in many feeds)
        if let mediaThumbnailURL = extractAttribute(from: xmlString, tag: "media:thumbnail", attribute: "url") {
            if let url = URL(string: mediaThumbnailURL) {
                return url
            }
        }
        
        // 3. Media content with image type
        if let mediaContentURL = extractMediaContentImage(from: xmlString) {
            if let url = URL(string: mediaContentURL) {
                return url
            }
        }
        
        // 4. Standard image tag
        if let imageURL = extractValue(from: xmlString, tag: "image") {
            if let url = URL(string: imageURL.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return url
            }
        }
        
        // 5. Enclosure with image type
        if let enclosureImageURL = extractImageEnclosure(from: xmlString) {
            if let url = URL(string: enclosureImageURL) {
                return url
            }
        }
        
        // 6. Fall back to podcast artwork
        return fallbackURL
    }
    
    private func extractMediaContentImage(from xmlString: String) -> String? {
        // Look for media:content tags with image MIME types
        let pattern = "<media:content[^>]*type=[\"']image/[^\"']*[\"'][^>]*url=[\"']([^\"']*)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        
        let range = NSRange(location: 0, length: xmlString.count)
        guard let match = regex.firstMatch(in: xmlString, options: [], range: range) else { return nil }
        
        let matchRange = match.range(at: 1)
        guard let swiftRange = Range(matchRange, in: xmlString) else { return nil }
        
        return String(xmlString[swiftRange])
    }
    
    private func extractImageEnclosure(from xmlString: String) -> String? {
        // Look for enclosure tags with image MIME types
        let pattern = "<enclosure[^>]*type=[\"']image/[^\"']*[\"'][^>]*url=[\"']([^\"']*)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        
        let range = NSRange(location: 0, length: xmlString.count)
        guard let match = regex.firstMatch(in: xmlString, options: [], range: range) else { return nil }
        
        let matchRange = match.range(at: 1)
        guard let swiftRange = Range(matchRange, in: xmlString) else { return nil }
        
        return String(xmlString[swiftRange])
    }
}

// MARK: - Supporting Types

/// Represents the current state of episode pagination
struct PaginationState {
    let episodes: [Episode]
    let currentPage: Int
    let hasMorePages: Bool
    let totalCount: Int
    let isLoading: Bool
    
    static let empty = PaginationState(
        episodes: [],
        currentPage: 0,
        hasMorePages: false,
        totalCount: 0,
        isLoading: false
    )
}
