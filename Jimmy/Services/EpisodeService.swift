import Foundation
import GRDB
import JimmyKit
import os

/// Episode fetching and streaming service.
/// Handles feed loading, pagination, and conditional requests.
final class EpisodeService {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "EpisodeService")
    static let shared = EpisodeService()

    // MARK: - Phase 4: Pagination Configuration
    private let defaultTimeout: TimeInterval = 30.0
    private let resourceTimeout: TimeInterval = 120.0

    private init() {}

    // MARK: - Core Fetching

    /// Fetches `podcastID`'s feed fresh over the network and parses it, through JimmyKit's
    /// `FeedFetcher`/`FeedParser` — the same path `AppModel.refresh(_:)` uses. Returns the parsed
    /// episodes directly; nothing here is written to the store (this mirrors today's behavior:
    /// the result was never persisted by the old `WorldClassIntegration`/`PodcastEngine` path
    /// either, just cached in memory and handed back to the caller).
    func fetchEpisodes(
        for podcastID: UUID,
        progressHandler: ((Episode, Int) -> Void)? = nil
    ) async throws -> [Episode] {
        guard let feedURL = await AppModel.current?.podcasts.first(where: { $0.id == podcastID })?.feedURL else {
            throw EpisodeServiceError.feedNotFound
        }

        let fetchResult = try await FeedFetcher().fetch(from: feedURL, etag: nil, lastModified: nil)
        let data: Data
        switch fetchResult {
        case .notModified:
            data = Data()
        case .fetched(let fetchedData, _, _):
            data = fetchedData
        }

        let parsed = try FeedParser.parse(data: data, podcastID: podcastID, feedURL: feedURL)
        let episodes = parsed.episodes.map { $0.asLegacyEpisode() }
        if let progressHandler {
            for (index, episode) in episodes.enumerated() {
                progressHandler(episode, index + 1)
            }
        }
        return episodes
    }
    
    /// Streams episodes from RSS feed URL using URLSession.bytes + XMLParser
    /// - Parameters:
    ///   - feedURL: RSS feed URL to stream from
    ///   - podcastID: ID of the podcast these episodes belong to
    /// - Returns: AsyncSequence that emits episodes as they're parsed
    func streamEpisodes(from feedURL: URL, podcastID: UUID) -> EpisodeAsyncSequence {
        return EpisodeAsyncSequence(feedURL: feedURL, podcastID: podcastID, )
    }
    
    // MARK: - Phase 5: Conditional GET Support
    
    /// Streams episodes with conditional GET support using ETag and If-Modified-Since headers
    /// Returns nil if server responds with 304 Not Modified
    /// - Parameters:
    ///   - feedURL: RSS feed URL to stream from
    ///   - podcastID: ID of the podcast these episodes belong to
    ///   - etag: Optional ETag from previous request
    ///   - lastModified: Optional Last-Modified date from previous request
    /// - Returns: Optional AsyncSequence that emits episodes, nil if 304 Not Modified
    func streamEpisodesConditional(
        from feedURL: URL, 
        podcastID: UUID,
        etag: String? = nil,
        lastModified: String? = nil
    ) -> ConditionalEpisodeAsyncSequence {
        return ConditionalEpisodeAsyncSequence(
            feedURL: feedURL, 
            podcastID: podcastID, 
            etag: etag,
            lastModified: lastModified,
            
        )
    }
    
    /// Checks if RSS feed has been modified using HEAD request
    /// - Parameters:
    ///   - feedURL: RSS feed URL to check
    ///   - etag: Optional ETag from previous request
    ///   - lastModified: Optional Last-Modified date from previous request
    /// - Returns: Tuple indicating if modified and new headers
    func checkFeedModified(
        feedURL: URL,
        etag: String? = nil,
        lastModified: String? = nil
    ) async throws -> (isModified: Bool, newEtag: String?, newLastModified: String?) {
        
        do {
            let response = try await UnifiedNetworkService.shared.performHeadRequest(url: feedURL)
            let responseEtag = response.value(forHTTPHeaderField: "ETag")
            let responseLastModified = response.value(forHTTPHeaderField: "Last-Modified")
            
            // Check ETag first (more reliable)
            if let etag = etag, let responseEtag = responseEtag {
                let isModified = etag != responseEtag
                return (isModified: isModified, newEtag: responseEtag, newLastModified: responseLastModified)
            }
            
            // Fallback to Last-Modified
            if let lastModified = lastModified, let responseLastModified = responseLastModified {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                
                if let lastModifiedDate = formatter.date(from: lastModified),
                   let responseLastModifiedDate = formatter.date(from: responseLastModified) {
                    let isModified = responseLastModifiedDate > lastModifiedDate
                    return (isModified: isModified, newEtag: responseEtag, newLastModified: responseLastModified)
                }
            }
            
            // If no conditional headers provided or parsing failed, assume modified
            return (isModified: true, newEtag: responseEtag, newLastModified: responseLastModified)
            
        } catch {
            // If HEAD fails, assume modified to proceed with GET request
            return (isModified: true, newEtag: nil, newLastModified: nil)
        }
    }

    // MARK: - Phase 4: Cursor-based Pagination
    
    /// Fetches a page of episodes with cursor-based pagination and timeout
    /// - Parameters:
    ///   - showID: UUID of the podcast/show
    ///   - cursor: Optional cursor for pagination (nil for first page)
    ///   - limit: Maximum number of episodes to return per page
    /// - Returns: Tuple containing episodes array and next cursor (nil if no more pages)
    func fetchPage(showID: UUID, cursor: String?, limit: Int) async throws -> (episodes: [Episode], nextCursor: String?) {
        
        // Create timeout task
        return try await withThrowingTaskGroup(of: (episodes: [Episode], nextCursor: String?).self) { group in
            
            // Add main fetch task
            group.addTask { [weak self] in
                guard let self = self else { 
                    throw EpisodeServiceError.serviceUnavailable 
                }
                return try await self.performPageFetch(showID: showID, cursor: cursor, limit: limit)
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.defaultTimeout * 1_000_000_000))
                throw EpisodeServiceError.timeout
            }
            
            // Return first completed task (either data or timeout)
            guard let result = try await group.next() else {
                throw EpisodeServiceError.unknown
            }
            
            // Cancel remaining tasks
            group.cancelAll()
            
            return result
        }
    }
    
    /// Fetches a page of episodes with conditional GET support
    /// - Parameters:
    ///   - showID: UUID of the podcast/show
    ///   - cursor: Optional cursor for pagination (nil for first page)
    ///   - limit: Maximum number of episodes to return per page
    ///   - etag: Optional ETag from previous request
    ///   - lastModified: Optional Last-Modified date from previous request
    /// - Returns: Tuple containing episodes array, next cursor, and new headers (nil if 304 Not Modified)
    func fetchPageConditional(
        showID: UUID, 
        cursor: String?, 
        limit: Int,
        etag: String? = nil,
        lastModified: String? = nil
    ) async throws -> (episodes: [Episode], nextCursor: String?, newEtag: String?, newLastModified: String?)? {
        
        // First check if feed is modified
        guard let feedURL = await getFeedURL(for: showID) else {
            throw EpisodeServiceError.feedNotFound
        }
        
        let (isModified, newEtag, newLastModified) = try await checkFeedModified(
            feedURL: feedURL,
            etag: etag,
            lastModified: lastModified
        )
        
        // If not modified, return nil to indicate 304 Not Modified
        if !isModified {
            return nil
        }
        
        // Feed is modified, proceed with normal fetch
        let (episodes, nextCursor) = try await fetchPage(showID: showID, cursor: cursor, limit: limit)
        return (episodes: episodes, nextCursor: nextCursor, newEtag: newEtag, newLastModified: newLastModified)
    }

    /// Internal method to perform the actual page fetch
    private func performPageFetch(showID: UUID, cursor: String?, limit: Int) async throws -> (episodes: [Episode], nextCursor: String?) {
        // For RSS feeds, we need to get the feed URL from the podcast
        // This is a simplified implementation - in a real app, you'd get this from your database
        guard let feedURL = await getFeedURL(for: showID) else {
            throw EpisodeServiceError.feedNotFound
        }
        
        // Parse cursor to determine starting position
        let startIndex = parseCursor(cursor) ?? 0
        let endIndex = startIndex + limit
        
        // Collect episodes from stream with pagination
        var collectedEpisodes: [Episode] = []
        var currentIndex = 0
        
        for try await episode in streamEpisodes(from: feedURL, podcastID: showID) {
            // PERF-04: Check for cancellation in long-running loop
            try Task.checkCancellation()
            
            // Skip episodes before our start index
            if currentIndex < startIndex {
                currentIndex += 1
                continue
            }
            
            // Stop if we've reached our limit
            if currentIndex >= endIndex {
                break
            }
            
            collectedEpisodes.append(episode)
            currentIndex += 1
        }
        
        // Generate next cursor if there might be more episodes
        let nextCursor = collectedEpisodes.count == limit ? createCursor(from: endIndex) : nil
        return (episodes: collectedEpisodes, nextCursor: nextCursor)
    }
    
    // MARK: - Phase 4: Cursor Utilities
    
    /// Parse cursor string to integer index
    private func parseCursor(_ cursor: String?) -> Int? {
        guard let cursor = cursor,
              let index = Int(cursor) else { return nil }
        return index
    }
    
    /// Create cursor string from integer index
    private func createCursor(from index: Int) -> String {
        return String(index)
    }
    
    /// Get feed URL for a podcast ID from repository
    private func getFeedURL(for showID: UUID) async -> URL? {
        do {
            // Use dependency injection to get podcast repository
            let podcastRepository = DIContainer.shared.podcastRepository
            let podcast = try await podcastRepository.fetchPodcast(id: showID, ignoreCache: false)
            return podcast?.feedURL
        } catch {
            return nil
        }
    }
}

// MARK: - Phase 4: Service Errors

enum EpisodeServiceError: Error, LocalizedError {
    case timeout
    case feedNotFound
    case serviceUnavailable
    case unknown
    case notModified
    
    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Request timed out"
        case .feedNotFound:
            return "Podcast feed not found"
        case .serviceUnavailable:
            return "Service temporarily unavailable"
        case .unknown:
            return "Unknown error occurred"
        case .notModified:
            return "Feed not modified (304)"
        }
    }
}

// MARK: - Phase 5: Conditional Episode Async Sequence

/// AsyncSequence that streams episodes with conditional GET support
struct ConditionalEpisodeAsyncSequence: AsyncSequence {
    typealias Element = ConditionalEpisodeResult
    
    private let feedURL: URL
    private let podcastID: UUID
    private let etag: String?
    private let lastModified: String?
    
    
    init(feedURL: URL, podcastID: UUID, etag: String?, lastModified: String?) {
        self.feedURL = feedURL
        self.podcastID = podcastID
        self.etag = etag
        self.lastModified = lastModified
        
    }
    
    func makeAsyncIterator() -> ConditionalEpisodeAsyncIterator {
        return ConditionalEpisodeAsyncIterator(
            feedURL: feedURL, 
            podcastID: podcastID,
            etag: etag,
            lastModified: lastModified,
            
        )
    }
}

/// Result type for conditional episode streaming
enum ConditionalEpisodeResult {
    case episode(Episode)
    case notModified(etag: String?, lastModified: String?)
    case headers(etag: String?, lastModified: String?)
}

/// AsyncIterator that handles conditional GET requests
final class ConditionalEpisodeAsyncIterator: NSObject, AsyncIteratorProtocol {
    typealias Element = ConditionalEpisodeResult
    
    private let feedURL: URL
    private let podcastID: UUID
    private let etag: String?
    private let lastModified: String?
    
    // State management
    private var hasStarted = false
    private var episodeIterator: EpisodeAsyncIterator?
    
    init(feedURL: URL, podcastID: UUID, etag: String?, lastModified: String?) {
        self.feedURL = feedURL
        self.podcastID = podcastID
        self.etag = etag
        self.lastModified = lastModified
        
        super.init()
    }
    
    func next() async -> ConditionalEpisodeResult? {
        if !hasStarted {
            hasStarted = true
            
            // First, try conditional GET
            do {
                let (_, response) = try await UnifiedNetworkService.shared.performRequestWithHeaders(
                    url: feedURL,
                    etag: etag,
                    lastModified: lastModified
                )
                
                let httpResponse = response as? HTTPURLResponse
                let newEtag = httpResponse?.allHeaderFields["Etag"] as? String ?? httpResponse?.allHeaderFields["ETag"] as? String
                let newLastModified = httpResponse?.allHeaderFields["Last-Modified"] as? String
                
                // Emit headers first
                let headersResult = ConditionalEpisodeResult.headers(etag: newEtag, lastModified: newLastModified)
                
                // Create episode iterator for streaming
                episodeIterator = EpisodeAsyncIterator(feedURL: feedURL, podcastID: podcastID, )
                
                return headersResult
                
            } catch let error as URLError where error.code == .cancelled {
                // 304 Not Modified - return appropriate result
                return ConditionalEpisodeResult.notModified(etag: etag, lastModified: lastModified)
            } catch {
                // Fallback to regular streaming
                episodeIterator = EpisodeAsyncIterator(feedURL: feedURL, podcastID: podcastID, )
                return ConditionalEpisodeResult.headers(etag: nil, lastModified: nil)
            }
        }
        
        // Stream episodes if we have an iterator
        if let iterator = episodeIterator,
           let episode = await iterator.next() {
            return ConditionalEpisodeResult.episode(episode)
        }
        
        return nil
    }
}

/// AsyncSequence that streams episodes from RSS feed using URLSession.bytes + XMLParser
struct EpisodeAsyncSequence: AsyncSequence {
    typealias Element = Episode
    
    private let feedURL: URL
    private let podcastID: UUID
    
    
    init(feedURL: URL, podcastID: UUID) {
        self.feedURL = feedURL
        self.podcastID = podcastID
        
    }
    
    func makeAsyncIterator() -> EpisodeAsyncIterator {
        return EpisodeAsyncIterator(feedURL: feedURL, podcastID: podcastID, )
    }
}

/// AsyncIterator that handles URLSession.bytes streaming + XMLParser
final class EpisodeAsyncIterator: NSObject, AsyncIteratorProtocol {
    typealias Element = Episode
    
    private let feedURL: URL
    private let podcastID: UUID
    
    
    // URLSession streaming state
    private var urlSessionTask: URLSessionDataTask?
    private var continuation: AsyncStream<Episode>.Continuation?
    private var stream: AsyncStream<Episode>?
    private var streamIterator: AsyncStream<Episode>.AsyncIterator?
    
    // XMLParser state
    private var xmlParser: XMLParser?
    private var currentElementName: String = ""
    private var isParsingItem: Bool = false
    private var episodeBuffer: String = ""
    private var itemDepth: Int = 0
    
    // Current episode being parsed
    private var currentTitle: String = ""
    private var currentAudioURL: String = ""
    private var currentDescription: String = ""
    private var currentPubDate: String = ""
    private var currentDuration: String = ""
    private var currentArtworkURL: String = ""
    
    // Data streaming
    private var accumulatedData = Data()
    private let chunkSize = 8192 // 8KB chunks
    
    // CRITICAL: Memory leak prevention
    private let maxBufferSize = 10 * 1024 * 1024 // 10MB max buffer
    private let cleanupThreshold = 5 * 1024 * 1024 // Clean up at 5MB
    
    init(feedURL: URL, podcastID: UUID) {
        self.feedURL = feedURL
        self.podcastID = podcastID
        
        super.init()
    }
    
    func next() async -> Episode? {
        if stream == nil {
            setupStream()
        }
        return await streamIterator?.next()
    }
    
    private func setupStream() {
        stream = AsyncStream<Episode> { continuation in
            self.continuation = continuation
            self.startStreaming()
            
            continuation.onTermination = { [weak self] _ in
                self?.cleanup()
            }
        }
        streamIterator = stream?.makeAsyncIterator()
    }
    
    private func startStreaming() {
        
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 120.0
        config.httpMaximumConnectionsPerHost = 2
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let session = URLSession(configuration: config)
        
        var request = URLRequest(url: self.feedURL)
        request.setValue("Jimmy/2.0 (iOS Podcast Client)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        
        Task {
            do {
                let (asyncBytes, response) = try await session.bytes(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      200...299 ~= httpResponse.statusCode else {
                    continuation?.finish()
                    return
                }
                // Process bytes as they arrive
                for try await byte in asyncBytes {
                    accumulatedData.append(byte)
                    
                    // Process in chunks to avoid blocking
                    if accumulatedData.count >= chunkSize {
                        await processDataChunk()
                    }
                }
                
                // Process any remaining data
                if !accumulatedData.isEmpty {
                    await processDataChunk()
                }
                
                // Finalize parsing
                await finalizeParsing()
                
            } catch {
                continuation?.finish()
            }
        }
    }
    
    @MainActor
    private func processDataChunk() {
        // CRITICAL: Prevent memory leak by limiting buffer size
        if accumulatedData.count > maxBufferSize {
            // Keep only recent data to avoid losing incomplete items
            let keepSize = cleanupThreshold
            let startIndex = max(0, accumulatedData.count - keepSize)
            accumulatedData = accumulatedData.subdata(in: startIndex..<accumulatedData.count)
        }
        
        guard let xmlString = String(data: accumulatedData, encoding: .utf8) else {
            return
        }
        
        // Look for complete <item>...</item> blocks
        let itemPattern = "<item[^>]*>(.*?)</item>"
        guard let regex = try? NSRegularExpression(pattern: itemPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return
        }
        
        let matches = regex.matches(in: xmlString, options: [], range: NSRange(location: 0, length: xmlString.count))
        
        for match in matches {
            guard let range = Range(match.range, in: xmlString) else { continue }
            let itemXML = String(xmlString[range])
            
            // Parse individual episode from XML
            if let episode = parseEpisodeFromXML(itemXML) {
                continuation?.yield(episode)
            }
        }
        
        // CRITICAL: Keep only unprocessed data (after last complete </item>)
        if let lastMatch = matches.last,
           let lastRange = Range(lastMatch.range, in: xmlString) {
            let remainingStartIndex = xmlString.index(lastRange.upperBound, offsetBy: 0)
            let remainingString = String(xmlString[remainingStartIndex...])
            accumulatedData = remainingString.data(using: .utf8) ?? Data()
        }
        
        // Additional cleanup if buffer is still too large
        if accumulatedData.count > cleanupThreshold {
            // Keep only the last portion to avoid losing incomplete items
            let keepSize = cleanupThreshold / 2
            let startIndex = max(0, accumulatedData.count - keepSize)
            accumulatedData = accumulatedData.subdata(in: startIndex..<accumulatedData.count)
        }
    }
    
    private func parseEpisodeFromXML(_ itemXML: String) -> Episode? {
        // Reset episode data
        currentTitle = ""
        currentAudioURL = ""
        currentDescription = ""
        currentPubDate = ""
        currentDuration = ""
        currentArtworkURL = ""
        
        // Create XMLParser for this item
        guard let data = itemXML.data(using: .utf8) else { return nil }
        let parser = XMLParser(data: data)
        parser.delegate = self
        
        guard parser.parse() else {
            return nil
        }
        
        // Create Episode from parsed data
        guard !currentTitle.isEmpty else {
            return nil
        }
        
        // Generate deterministic UUID based on feed URL and episode data
        let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let publishedDate = parseDate(from: currentPubDate)
        let audioURL = URL(string: currentAudioURL)
        
        let deterministicID = DeterministicUUIDGenerator.generateEpisodeID(
            feedURL: feedURL,
            audioURL: audioURL,
            title: title,
            publishedDate: publishedDate
        )
        
        let episode = Episode(
            id: deterministicID,
            title: title,
            podcastID: podcastID,
            publishedDate: publishedDate,
            duration: parseDuration(from: currentDuration),
            artworkURL: URL(string: currentArtworkURL),
            description: currentDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            audioURL: audioURL
        )
        
        return episode
    }
    
    private func parseDate(from dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
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
        
        return nil
    }
    
    private func parseDuration(from durationString: String) -> TimeInterval? {
        let trimmed = durationString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try parsing as seconds first
        if let seconds = Double(trimmed) {
            return seconds
        }
        
        // Try parsing as HH:MM:SS or MM:SS format
        let components = trimmed.components(separatedBy: ":")
        if components.count == 3 {
            // HH:MM:SS
            guard let hours = Double(components[0]),
                  let minutes = Double(components[1]),
                  let seconds = Double(components[2]) else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        } else if components.count == 2 {
            // MM:SS
            guard let minutes = Double(components[0]),
                  let seconds = Double(components[1]) else { return nil }
            return minutes * 60 + seconds
        }
        
        return nil
    }
    
    @MainActor
    private func finalizeParsing() {
        continuation?.finish()
    }
    
    private func cleanup() {
        urlSessionTask?.cancel()
        xmlParser?.abortParsing()
        continuation?.finish()
    }
}

// MARK: - XMLParserDelegate
extension EpisodeAsyncIterator: XMLParserDelegate {
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElementName = elementName.lowercased()
        
        if currentElementName == "item" {
            isParsingItem = true
            itemDepth += 1
        } else if isParsingItem && itemDepth == 1 {
            // We're inside an item, reset buffer for this element
            episodeBuffer = ""
            
            // Handle enclosure tag for audio URL
            if currentElementName == "enclosure" {
                if let url = attributeDict["url"], let type = attributeDict["type"], type.contains("audio") {
                    currentAudioURL = url
                }
            }
            
            // Handle iTunes image
            if currentElementName == "itunes:image" || currentElementName == "image" {
                if let href = attributeDict["href"] {
                    currentArtworkURL = href
                }
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isParsingItem && itemDepth == 1 {
            episodeBuffer += string
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = elementName.lowercased()
        
        if element == "item" {
            isParsingItem = false
            itemDepth = max(0, itemDepth - 1)
        } else if isParsingItem && itemDepth == 1 {
            let content = episodeBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            
            switch element {
            case "title":
                currentTitle = content
            case "description", "itunes:summary", "content:encoded":
                if currentDescription.isEmpty || element == "content:encoded" {
                    currentDescription = content
                }
            case "pubdate", "published":
                currentPubDate = content
            case "itunes:duration":
                currentDuration = content
            case "link":
                if currentAudioURL.isEmpty {
                    currentAudioURL = content
                }
            default:
                break
            }
        }
    }
    
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
    }
}

// MARK: - Episode Status Management
extension EpisodeService {
    
    /// Get episode with status loaded from database (if it exists)
    /// - Parameter episode: Episode to find in database
    /// - Returns: Existing episode with status, or nil if not found
    func getEpisodeWithStatus(_ episode: Episode) async throws -> Episode? {
        do {
            // CRITICAL FIX: Use direct ID lookup first - much more reliable and faster
            let existingEpisode = try await DatabaseManager.shared.readAsync { db in
                try Episode.fetchOne(db, key: episode.id)
            }
            
            if let existingEpisode = existingEpisode {
                return existingEpisode
            }
            
            // Fallback: If ID lookup fails, try audioURL lookup
            if let audioURL = episode.audioURL {
                return try await findEpisodeByAudioURL(audioURL)
            }
            
        } catch {
            Self.logger.warning("EpisodeService: Failed to fetch existing episode by ID \(episode.id): \(error)")
            
            // Final fallback: Search by audioURL if available
            if let audioURL = episode.audioURL {
                return try? await findEpisodeByAudioURL(audioURL)
            }
        }
        return nil
    }
    
    /// Fallback method to find episode by audio URL when podcast ID lookup fails
    private func findEpisodeByAudioURL(_ audioURL: URL?) async throws -> Episode? {
        guard let audioURL = audioURL else { return nil }
        
        // Search in database directly by audio URL
        return try await DatabaseManager.shared.readAsync { db in
            try Episode.filter(Episode.Columns.audioURL == audioURL).fetchOne(db)
        }
    }
    
    /// Updates episode status in background thread and publishes changes on main thread
    /// - Parameters:
    ///   - episode: Episode to update
    ///   - status: New status to set
    func updateEpisodeStatus(_ episode: Episode, status: EpisodeStatus) {
        Self.logger.debug("EpisodeService: updateEpisodeStatus called for \(episode.title) (ID: \(episode.id)) with status: \(String(status.rawValue))")
        
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            var updatedEpisode = episode
            let oldStatus = episode.status
            updatedEpisode.status = status
            
            let beforeStatusStr = String(updatedEpisode.status.rawValue)
            Self.logger.debug("EpisodeService: Before database update - Title: \(updatedEpisode.title), ID: \(updatedEpisode.id), Status: \(beforeStatusStr)")
            
            // Persist to database
            await self.persistEpisodeStatus(updatedEpisode)
            
            let afterStatusStr = String(updatedEpisode.status.rawValue)
            Self.logger.debug("EpisodeService: After database update - Title: \(updatedEpisode.title), ID: \(updatedEpisode.id), Status: \(afterStatusStr)")
            
            // CRITICAL FIX: Update playback state when played status changes
            let wasPlayed = oldStatus.contains(.played)
            let isNowPlayed = status.contains(.played)
            
            if wasPlayed != isNowPlayed {
                if isNowPlayed {
                    await self.updatePlaybackStateAsFinished(for: episode)
                } else {
                    await self.updatePlaybackStateAsUnfinished(for: episode)
                }
            }
            
            // ⚠️ CRITICAL WARNING: DO NOT REMOVE OR MODIFY THIS NOTIFICATION POSTING
            //
            // PURPOSE: Broadcasts episode status changes to all listening views for real-time UI updates
            // LISTENERS: DatabaseEpisodeListView, LibraryViewModel, QueueView, and other episode views
            //
            // FLOW: User action → updateEpisodeStatus() → database update → THIS NOTIFICATION → UI updates
            //
            // ESSENTIAL FOR: 
            // - Real-time episode status sync across PodcastDetailView, LibraryView, QueueView
            // - Preventing "episode doesn't update" bugs reported by users
            // - Cross-view consistency when marking episodes as played/unplayed
            //
            // NOTIFICATION PAYLOAD: updatedEpisode object with new status
            // THREAD SAFETY: Posted on main thread to ensure UI updates work correctly
            //
            // ⚠️ MODIFICATION WARNING: Removing this breaks real-time episode status updates across the app
            // Emit change on main thread
            Task { @MainActor in
                // CRITICAL FIX: Ensure played field matches status for UI compatibility
                updatedEpisode.played = updatedEpisode.status.contains(.played)
                
                Self.logger.debug("EpisodeService: Sending notification for \(updatedEpisode.title) with status: \(String(updatedEpisode.status.rawValue))")
                
                NotificationCenter.default.post(
                    name: .episodeStatusUpdated,
                    object: updatedEpisode
                )
                
                Self.logger.debug("EpisodeService: Posted episodeStatusUpdated notification for \(updatedEpisode.title)")
            }
        }
    }
    
    /// Sets episode as played (progress > 95%)
    /// - Parameter episode: Episode to mark as played
    func setEpisodePlayed(_ episode: Episode) {
        Self.logger.debug("EpisodeService: setEpisodePlayed called for \(episode.title) (ID: \(episode.id))")
        
        var newStatus = episode.status
        newStatus.insert(.played)
        
        let newStatusStr = String(newStatus.rawValue)
        Self.logger.debug("EpisodeService: About to call updateEpisodeStatus with new status: \(newStatusStr)")
        updateEpisodeStatus(episode, status: newStatus)
        
        // NOTE: updateEpisodeStatus already calls updatePlaybackStateAsFinished when played status changes
    }
    
    /// Sets episode as queued
    /// - Parameter episode: Episode to add to queue
    func setEpisodeQueued(_ episode: Episode) {
        // print("🎯 EpisodeService: Setting episode as QUEUED: '\(episode.title)'")
        var newStatus = episode.status
        newStatus.insert(.queued)
        updateEpisodeStatus(episode, status: newStatus)
    }
    
    /// Removes episode from queue
    /// - Parameter episode: Episode to remove from queue
    func removeEpisodeFromQueue(_ episode: Episode) {
        var newStatus = episode.status
        newStatus.remove(.queued)
        updateEpisodeStatus(episode, status: newStatus)
    }
    
    /// Sets episode as currently playing (clears playing status from other episodes)
    /// - Parameter episode: Episode that is now playing
    func setEpisodePlaying(_ episode: Episode) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            // First, clear playing status from all other episodes
            await self.clearAllPlayingStatus()
            
            // Then set this episode as playing
            var newStatus = episode.status
            newStatus.insert(.playing)
            self.updateEpisodeStatus(episode, status: newStatus)
        }
    }
    
    /// Clears playing status from episode
    /// - Parameter episode: Episode to stop playing
    func clearEpisodePlaying(_ episode: Episode) {
        var newStatus = episode.status
        newStatus.remove(.playing)
        updateEpisodeStatus(episode, status: newStatus)
    }
    
    /// Private method to persist episode status to database
    private func persistEpisodeStatus(_ episode: Episode) async {
        do {
            try await DatabaseManager.shared.writeAsync { db in
                // First check if episode exists
                let exists = try Episode.fetchOne(db, key: episode.id) != nil
                
                if exists {
                    // CRITICAL FIX: Update both status and legacy played field for UI compatibility
                    let isPlayed = episode.status.contains(.played)
                    try db.execute(sql: """
                        UPDATE episodes 
                        SET status = ?, played = ? 
                        WHERE id = ?
                    """, arguments: [episode.status.rawValue, isPlayed, episode.id])
                    
                    let dbStatusStr = String(episode.status.rawValue)
                    Self.logger.debug("EpisodeService: Updated episode in database - Status: \(dbStatusStr), Played: \(isPlayed)")
                } else {
                    // Episode doesn't exist, check if we have the podcastID
                    if episode.podcastID != nil {
                        // CRITICAL FIX: Ensure played field matches status when saving new episode
                        var episodeToSave = episode
                        episodeToSave.played = episode.status.contains(.played)
                        
                        try episodeToSave.save(db)
                        Self.logger.debug("EpisodeService: Saved new episode - Status: \(String(episode.status.rawValue)), Played: \(episodeToSave.played)")
                    } else {
                        // Cannot save episode without podcastID
                        throw DatabaseError.operationFailed(
                            NSError(domain: "EpisodeService", code: 1001, userInfo: [
                                NSLocalizedDescriptionKey: "Cannot save episode without podcastID: \(episode.id)"
                            ])
                        )
                    }
                }
            }
        } catch {
            Self.logger.fault("CRITICAL: Failed to persist episode status: \(error)")
            
            // If it's a "Key not found" error, try to find the episode in memory and update its podcastID
            if error.localizedDescription.contains("Key not found") {
                await handleMissingEpisode(episode)
            }
        }
    }
    
    /// Handle the case where an episode is not found in the database
    private func handleMissingEpisode(_ episode: Episode) async {

        
        // Try to find the episode in memory with a podcastID
        // This is a fallback mechanism for episodes that haven't been persisted yet
        Task { @MainActor in
            // Post a notification that this episode needs to be found and saved
            NotificationCenter.default.post(
                name: .episodeMissingFromDatabase,
                object: episode
            )
        }
    }
    
    /// Private method to clear playing status from all episodes
    private func clearAllPlayingStatus() async {
        do {
            try await DatabaseManager.shared.writeAsync { db in
                try db.execute(sql: """
                    UPDATE episodes 
                    SET status = status & ~4 
                    WHERE status & 4 = 4
                """)
            }
        } catch {
            Self.logger.fault("CRITICAL: Failed to clear playing status: \(error)")
        }
    }
    
    /// Updates playback state to mark episode as finished
    /// This ensures the UI shows the episode as played
    private func updatePlaybackStateAsFinished(for episode: Episode) async {
        do {
            let playbackStateRepository = DIContainer.shared.playbackStateRepository
            
            // Get current playback state or create new one
            let currentState = (try? await playbackStateRepository.fetchPlaybackState(for: episode.id)) ?? 
                               PlaybackState(episodeID: episode.id, position: 0, finished: false)
            
            // Update to finished
            let updatedState = PlaybackState(
                episodeID: episode.id,
                position: currentState.position,
                finished: true,
                updatedAt: Date()
            )
            
            try await playbackStateRepository.savePlaybackState(updatedState)
        } catch {
            Self.logger.fault("CRITICAL: Failed to update playback state as finished: \(error)")
        }
    }
    
    /// Updates playback state to mark episode as unfinished
    /// This ensures the UI shows the episode as unplayed
    private func updatePlaybackStateAsUnfinished(for episode: Episode) async {
        do {
            let playbackStateRepository = DIContainer.shared.playbackStateRepository
            
            // Get current playback state or create new one
            let currentState = (try? await playbackStateRepository.fetchPlaybackState(for: episode.id)) ?? 
                               PlaybackState(episodeID: episode.id, position: 0, finished: false)
            
            // Update to not finished
            let updatedState = PlaybackState(
                episodeID: episode.id,
                position: currentState.position,
                finished: false,
                updatedAt: Date()
            )
            
            try await playbackStateRepository.savePlaybackState(updatedState)
        } catch {
            Self.logger.fault("CRITICAL: Failed to update playback state as unfinished: \(error)")
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let episodeStatusUpdated = Notification.Name("episodeStatusUpdated")
    static let episodeMissingFromDatabase = Notification.Name("episodeMissingFromDatabase")
} 
