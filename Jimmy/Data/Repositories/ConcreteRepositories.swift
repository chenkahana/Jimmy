import Foundation
import Combine

// MARK: - Concrete Repository Implementations
// Handle actual data operations with network, storage, and parsing

/// Concrete implementation of podcast repository
final class ConcretePodcastRepository: PodcastRepositoryProtocol {
    private let networkRepository: NetworkRepositoryProtocol
    private let storageRepository: StorageRepositoryProtocol
    private let rssParser: RSSParserProtocol
    private let changesSubject = PassthroughSubject<PodcastChanges, Never>()
    
    private let podcastsKey = "podcasts_v2"
    
    init(
        networkRepository: NetworkRepositoryProtocol,
        storageRepository: StorageRepositoryProtocol,
        rssParser: RSSParserProtocol
    ) {
        self.networkRepository = networkRepository
        self.storageRepository = storageRepository
        self.rssParser = rssParser
    }
    
    func fetchPodcasts() async throws -> [Podcast] {
        // Load from local storage first
        if let podcasts = try await storageRepository.load([Podcast].self, from: podcastsKey) {
            return podcasts
        }
        return []
    }
    
    func fetchPodcastWithEpisodes(from feedURL: URL) async throws -> (Podcast, [Episode]) {
        // Check network connectivity
        guard await networkRepository.isConnected else {
            throw PodcastRepositoryError.networkUnavailable
        }
        
        // Fetch RSS data
        let rssData = try await networkRepository.fetchRSSFeed(from: feedURL)
        
        // Parse RSS to get podcast and episodes
        let podcastID = UUID()
        let (episodes, metadata) = try await rssParser.parse(data: rssData, podcastID: podcastID)
        
        guard let title = metadata.title, !title.isEmpty else {
            throw PodcastRepositoryError.invalidRSSFeed
        }
        
        let podcast = Podcast(
            id: podcastID,
            title: title,
            author: metadata.author ?? "",
            description: metadata.description ?? "",
            feedURL: feedURL,
            artworkURL: metadata.artworkURL,
            lastEpisodeDate: episodes.compactMap(\.publishedDate).max()
        )
        
        return (podcast, episodes)
    }
    
    func savePodcasts(_ podcasts: [Podcast]) async throws {
        try await storageRepository.save(podcasts, to: podcastsKey)
        
        // Notify observers
        Task { @MainActor in
            // For save operations, we don't have old/new comparison, so we'll just notify of updates
            let changes = PodcastChanges(added: [], removed: [], updated: podcasts)
            changesSubject.send(changes)
        }
    }
    
    func deletePodcastData(id: UUID) async throws {
        // Load current podcasts
        var podcasts = try await fetchPodcasts()
        
        // Find and remove the podcast
        if let index = podcasts.firstIndex(where: { $0.id == id }) {
            let removedPodcast = podcasts.remove(at: index)
            
            // Save updated list
            try await savePodcasts(podcasts)
            
            // Notify observers
            Task { @MainActor in
                let changes = PodcastChanges(added: [], removed: [removedPodcast], updated: [])
                changesSubject.send(changes)
            }
        }
    }
    
    var podcastChangesPublisher: AnyPublisher<PodcastChanges, Never> {
        changesSubject.eraseToAnyPublisher()
    }
}

/// Concrete implementation of episode repository
final class ConcreteEpisodeRepository: EpisodeRepositoryProtocol {
    private let networkRepository: NetworkRepositoryProtocol
    private let storageRepository: StorageRepositoryProtocol
    private let podcastRepository: PodcastRepositoryProtocol
    private let rssParser: RSSParserProtocol
    private let changesSubject = PassthroughSubject<CleanEpisodeChanges, Never>()
    
    private let episodesKey = "episodes_v2"
    
    init(
        networkRepository: NetworkRepositoryProtocol,
        storageRepository: StorageRepositoryProtocol,
        podcastRepository: PodcastRepositoryProtocol,
        rssParser: RSSParserProtocol
    ) {
        self.networkRepository = networkRepository
        self.storageRepository = storageRepository
        self.podcastRepository = podcastRepository
        self.rssParser = rssParser
    }
    
    func fetchEpisodes(for podcastID: UUID) async throws -> [Episode] {
        // First, try to get the podcast to get its RSS feed URL
        let allPodcasts = try await podcastRepository.fetchPodcasts()
        guard let podcast = allPodcasts.first(where: { $0.id == podcastID }) else {
            // If podcast not found, fall back to loading from storage
            let allEpisodes = try await fetchAllEpisodes()
            return allEpisodes.filter { $0.podcastID == podcastID }
        }
        
        // Fetch fresh episodes from RSS feed
        do {
            let rssData = try await networkRepository.fetchRSSFeed(from: podcast.feedURL)
            let (episodes, _) = try await rssParser.parse(data: rssData, podcastID: podcastID)
            
            // Save the fetched episodes to storage
            var allEpisodes = try await fetchAllEpisodes()
            
            // Remove old episodes for this podcast
            allEpisodes.removeAll { $0.podcastID == podcastID }
            
            // Add new episodes
            allEpisodes.append(contentsOf: episodes)
            
            // Save updated episodes
            try await saveEpisodes(allEpisodes)
            
            return episodes
        } catch {
            // If RSS fetch fails, fall back to cached episodes
            print("⚠️ Failed to fetch episodes from RSS, using cached: \(error)")
            let allEpisodes = try await fetchAllEpisodes()
            return allEpisodes.filter { $0.podcastID == podcastID }
        }
    }
    
    func fetchAllEpisodes() async throws -> [Episode] {
        if let episodes = try await storageRepository.load([Episode].self, from: episodesKey) {
            return episodes
        }
        return []
    }
    
    func saveEpisodes(_ episodes: [Episode]) async throws {
        try await storageRepository.save(episodes, to: episodesKey)
        
        // Notify observers
        Task { @MainActor in
            let changes = CleanEpisodeChanges(added: [], removed: [], updated: episodes)
            changesSubject.send(changes)
        }
    }
    
    func deleteEpisodes(forPodcastID podcastID: UUID) async throws {
        var allEpisodes = try await fetchAllEpisodes()
        let episodesToRemove = allEpisodes.filter { $0.podcastID == podcastID }
        
        allEpisodes.removeAll { $0.podcastID == podcastID }
        try await saveEpisodes(allEpisodes)
        
        // Notify observers
        if !episodesToRemove.isEmpty {
            Task { @MainActor in
                let changes = CleanEpisodeChanges(added: [], removed: episodesToRemove, updated: [])
                changesSubject.send(changes)
            }
        }
    }
    
    var episodeChangesPublisher: AnyPublisher<CleanEpisodeChanges, Never> {
        changesSubject.eraseToAnyPublisher()
    }
}

/// Concrete implementation of network repository
final class ConcreteNetworkRepository: NetworkRepositoryProtocol {
    private let session: URLSession
    private let networkMonitor: NetworkMonitorProtocol
    
    init(session: URLSession = .shared, networkMonitor: NetworkMonitorProtocol) {
        self.session = session
        self.networkMonitor = networkMonitor
    }
    
    func fetchRSSFeed(from url: URL) async throws -> Data {
        guard await isConnected else {
            throw NetworkRepositoryError.noConnection
        }
        
        let request = URLRequest(url: url, timeoutInterval: 30.0)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkRepositoryError.invalidResponse
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                throw NetworkRepositoryError.httpError(httpResponse.statusCode)
            }
            
            return data
        } catch {
            if error is URLError {
                throw NetworkRepositoryError.networkError(error)
            }
            throw error
        }
    }
    
    func downloadEpisodeAudio(from url: URL) async throws -> URL {
        guard await isConnected else {
            throw NetworkRepositoryError.noConnection
        }
        
        let (tempURL, response) = try await session.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw NetworkRepositoryError.downloadFailed
        }
        
        // Move to permanent location
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsURL.appendingPathComponent(url.lastPathComponent)
        
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        return destinationURL
    }
    
    var isConnected: Bool {
        get async {
            await networkMonitor.isConnected
        }
    }
}

/// Concrete implementation of storage repository
final class ConcreteStorageRepository: StorageRepositoryProtocol {
    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }
    
    func save<T: Codable>(_ data: T, to key: String) async throws {
        let encodedData = try encoder.encode(data)
        userDefaults.set(encodedData, forKey: key)
        
        // Also save to iCloud if enabled
        // Note: AppDataDocument integration would go here in production
    }
    
    func load<T: Codable>(_ type: T.Type, from key: String) async throws -> T? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }
        
        return try decoder.decode(type, from: data)
    }
    
    func delete(key: String) async throws {
        userDefaults.removeObject(forKey: key)
    }
    
    func exists(key: String) async -> Bool {
        return userDefaults.object(forKey: key) != nil
    }
}

// MARK: - Supporting Protocols and Types

/// Protocol for RSS parsing operations
protocol RSSParserProtocol {
    func parse(data: Data, podcastID: UUID) async throws -> ([Episode], RSSMetadata)
}

/// Protocol for network monitoring
protocol NetworkMonitorProtocol {
    var isConnected: Bool { get async }
}

/// RSS metadata structure
struct RSSMetadata {
    let title: String?
    let author: String?
    let description: String?
    let artworkURL: URL?
}

/// Concrete RSS parser implementation
final class ConcreteRSSParser: RSSParserProtocol {
    func parse(data: Data, podcastID: UUID) async throws -> ([Episode], RSSMetadata) {
        // Parse the RSS data
        do {
            // Convert data to string to get URL (this is a simplified approach)
            // In a real implementation, you'd parse the RSS XML directly
            guard let xmlString = String(data: data, encoding: .utf8) else {
                throw RSSParserError.invalidData
            }
            
            // Extract basic metadata from XML
            let metadata = extractMetadata(from: xmlString)
            
            // Parse episodes from XML
            let episodes = try await parseEpisodes(from: xmlString, podcastID: podcastID)
            
            return (episodes, metadata)
        } catch {
            throw RSSParserError.parsingFailed(error)
        }
    }
    
    private func extractMetadata(from xmlString: String) -> RSSMetadata {
        // Simple XML parsing for metadata
        let title = extractValue(from: xmlString, tag: "title")
        let author = extractValue(from: xmlString, tag: "itunes:author") ?? 
                    extractValue(from: xmlString, tag: "author")
        let description = extractValue(from: xmlString, tag: "description")
        
        // Extract artwork URL
        var artworkURL: URL?
        if let artworkString = extractValue(from: xmlString, tag: "itunes:image") {
            artworkURL = URL(string: artworkString)
        }
        
        return RSSMetadata(
            title: title,
            author: author,
            description: description,
            artworkURL: artworkURL
        )
    }
    
    private func parseEpisodes(from xmlString: String, podcastID: UUID) async throws -> [Episode] {
        // This is a simplified implementation
        // In production, you'd use a proper XML parser like XMLParser or a third-party library
        
        var episodes: [Episode] = []
        
        // Split by <item> tags to get individual episodes
        let itemComponents = xmlString.components(separatedBy: "<item>")
        
        for (index, itemString) in itemComponents.enumerated() {
            guard index > 0 else { continue } // Skip the first component (before first <item>)
            
            let title = extractValue(from: itemString, tag: "title") ?? "Unknown Episode"
            let description = extractValue(from: itemString, tag: "description")
            let audioURLString = extractAttribute(from: itemString, tag: "enclosure", attribute: "url")
            let pubDateString = extractValue(from: itemString, tag: "pubDate")
            
            // Extract episode-specific artwork
            let episodeArtworkURL = extractEpisodeArtwork(from: itemString)
            
            // Parse publication date
            let publishedDate = parsePubDate(pubDateString) ?? Date()
            
            // Create episode
            let episode = Episode(
                id: UUID(),
                title: title,
                artworkURL: episodeArtworkURL,
                audioURL: audioURLString.flatMap { URL(string: $0) },
                description: description,
                played: false,
                podcastID: podcastID,
                publishedDate: publishedDate,
                localFileURL: nil,
                playbackPosition: 0
            )
            
            episodes.append(episode)
        }
        
        return episodes
    }
    
    private func extractValue(from xml: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]*)</\(tag)>"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        
        if let match = regex?.firstMatch(in: xml, options: [], range: range),
           let valueRange = Range(match.range(at: 1), in: xml) {
            return String(xml[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    private func extractAttribute(from xml: String, tag: String, attribute: String) -> String? {
        let pattern = "<\(tag)[^>]*\(attribute)=\"([^\"]*)\""
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        
        if let match = regex?.firstMatch(in: xml, options: [], range: range),
           let valueRange = Range(match.range(at: 1), in: xml) {
            return String(xml[valueRange])
        }
        
        return nil
    }
    
    private func parsePubDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: dateString)
    }
    
    private func extractEpisodeArtwork(from itemString: String) -> URL? {
        // Try multiple common episode artwork tags in order of preference
        
        // 1. iTunes episode image (most common)
        if let itunesImageURL = extractAttribute(from: itemString, tag: "itunes:image", attribute: "href") {
            return URL(string: itunesImageURL)
        }
        
        // 2. Media thumbnail (common in many feeds)
        if let mediaThumbnailURL = extractAttribute(from: itemString, tag: "media:thumbnail", attribute: "url") {
            return URL(string: mediaThumbnailURL)
        }
        
        // 3. Media content with image type
        if let mediaContentURL = extractMediaContentImage(from: itemString) {
            return URL(string: mediaContentURL)
        }
        
        // 4. Standard image tag
        if let imageURL = extractValue(from: itemString, tag: "image") {
            return URL(string: imageURL.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        // 5. Enclosure with image type
        if let enclosureImageURL = extractImageEnclosure(from: itemString) {
            return URL(string: enclosureImageURL)
        }
        
        // No episode-specific artwork found
        return nil
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

enum RSSParserError: Error {
    case invalidData
    case parsingFailed(Error)
}

/// Simple network monitor implementation
final class ConcreteNetworkMonitor: NetworkMonitorProtocol {
    var isConnected: Bool {
        get async {
            // Simple implementation - in production, use Network framework
            return true
        }
    }
}

// MARK: - Error Types

enum PodcastRepositoryError: LocalizedError {
    case networkUnavailable
    case invalidRSSFeed
    case parsingError
    
    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Network connection unavailable"
        case .invalidRSSFeed:
            return "Invalid RSS feed format"
        case .parsingError:
            return "Failed to parse podcast data"
        }
    }
}

enum NetworkRepositoryError: LocalizedError {
    case noConnection
    case invalidResponse
    case httpError(Int)
    case networkError(Error)
    case downloadFailed
    
    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No network connection"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .downloadFailed:
            return "Download failed"
        }
    }
} 