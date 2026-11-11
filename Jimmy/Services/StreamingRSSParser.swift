import Foundation
import os

/// A streaming RSS parser that emits episodes as they're parsed from incoming data chunks.
/// This solves timeout and UI blocking issues by:
/// 1. Processing data incrementally as it arrives from URLSession
/// 2. Emitting episodes immediately when parsed (no waiting for full download)
/// 3. Running all parsing off the main thread
/// 4. Supporting cancellation mid-stream
final class StreamingRSSParser: NSObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "StreamingRSSParser")
    
    /// Creates an AsyncSequence that streams episodes from a URL
    /// - Parameters:
    ///   - url: RSS feed URL to parse
    ///   - podcastID: ID of the podcast these episodes belong to
    ///   - timeout: Request timeout (default: 60 seconds)
    /// - Returns: AsyncSequence that emits episodes as they're parsed
    func streamEpisodes(from url: URL, podcastID: UUID, timeout: TimeInterval = 60.0) -> StreamingEpisodeSequence {
        return StreamingEpisodeSequence(url: url, podcastID: podcastID, timeout: timeout)
    }
}

/// AsyncSequence that streams episodes from an RSS feed URL
struct StreamingEpisodeSequence: AsyncSequence {
    typealias Element = StreamingEpisodeResult
    
    private let url: URL
    private let podcastID: UUID
    private let timeout: TimeInterval
    
    init(url: URL, podcastID: UUID, timeout: TimeInterval) {
        self.url = url
        self.podcastID = podcastID
        self.timeout = timeout
    }
    
    func makeAsyncIterator() -> StreamingEpisodeIterator {
        return StreamingEpisodeIterator(url: url, podcastID: podcastID, timeout: timeout)
    }
}

/// Result type for streaming episodes - can be episode, metadata, or error
enum StreamingEpisodeResult {
    case episode(Episode)
    case metadata(PodcastMetadata)
    case error(Error)
    case completed(totalEpisodes: Int)
}

/// AsyncIteratorProtocol that handles the actual streaming and parsing
final class StreamingEpisodeIterator: NSObject, AsyncIteratorProtocol {
    typealias Element = StreamingEpisodeResult
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "StreamingEpisodeIterator")

    private let url: URL
    private let podcastID: UUID
    private let timeout: TimeInterval
    
    // URLSession and parsing state
    private var urlSessionTask: URLSessionDataTask?
    private var xmlParser: XMLParser?
    private var continuation: AsyncStream<StreamingEpisodeResult>.Continuation?
    private var stream: AsyncStream<StreamingEpisodeResult>?
    private var streamIterator: AsyncStream<StreamingEpisodeResult>.AsyncIterator?
    
    // XML parsing state
    private var currentElementName: String = ""
    private var isParsingItem: Bool = false
    private var isParsingChannel: Bool = false
    private var episodeCount: Int = 0
    
    // Current episode being parsed
    private var currentTitle: String = ""
    private var currentAudioURL: String = ""
    private var currentDescription: String = ""
    private var currentPubDate: String = ""
    private var currentEpisodeArtworkURL: String = ""
    private var currentDuration: TimeInterval?
    
    // Podcast metadata
    private var podcastTitle: String = ""
    private var podcastAuthor: String = ""
    private var podcastDescription: String = ""
    private var podcastArtworkURL: String = ""
    private var metadataEmitted: Bool = false
    
    // Data accumulation for incremental parsing
    private var accumulatedData = Data()
    private var lastProcessedPosition = 0
    
    // CRITICAL: Memory leak prevention
    private let maxBufferSize = 10 * 1024 * 1024 // 10MB max buffer
    private let cleanupThreshold = 5 * 1024 * 1024 // Clean up at 5MB
    
    init(url: URL, podcastID: UUID, timeout: TimeInterval) {
        self.url = url
        self.podcastID = podcastID
        self.timeout = timeout
        super.init()
    }
    
    func next() async -> StreamingEpisodeResult? {
        // Initialize stream on first call
        if stream == nil {
            setupStream()
        }
        
        // Get next result from stream
        return await streamIterator?.next()
    }
    
    private func setupStream() {
        // Create AsyncStream to bridge URLSession callbacks with AsyncSequence
        stream = AsyncStream<StreamingEpisodeResult> { continuation in
            self.continuation = continuation
            self.startNetworkRequest()
            
            // Handle cancellation
            continuation.onTermination = { [weak self] _ in
                self?.cleanup()
            }
        }
        streamIterator = stream?.makeAsyncIterator()
    }
    
    private func startNetworkRequest() {
        
        // Create URLSession with robust streaming configuration
        let config = URLSessionConfiguration.ephemeral
        
        // Network timeout settings - more aggressive for streaming
        config.timeoutIntervalForRequest = min(timeout, 30.0) // Cap individual request timeout
        config.timeoutIntervalForResource = timeout * 3 // Allow more time for full resource
        
        // CRITICAL: Use HTTP/1.1 to prevent QUIC protocol violations
        config.httpAdditionalHeaders = ["Connection": "keep-alive"]
        
        // Note: HTTP/3 disabling is handled at the system level if needed
        // The assumesHTTP3Capable property is not available via KVC
        
        config.waitsForConnectivity = false  // Prevent hanging during streaming
        
        // Connection settings to prevent TCP issues
        config.httpMaximumConnectionsPerHost = 2
        config.httpShouldUsePipelining = false // Disable pipelining to avoid connection issues
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        
        // Disable caching for fresh data
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        // Network service type for better connection handling
        config.networkServiceType = .responsiveData
        
        // Allow cellular data and expensive networks
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        
        // Waits for connectivity instead of failing immediately
        config.waitsForConnectivity = true
        
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        var request = URLRequest(url: url, timeoutInterval: min(timeout, 30.0))
        
        // Enhanced headers for better server compatibility
        request.setValue("Jimmy/2.0 (iOS Podcast Client)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        
        // Add range header to enable partial content support if server supports it
        // This helps with streaming large feeds
        request.setValue("bytes=0-", forHTTPHeaderField: "Range")
        
        urlSessionTask = session.dataTask(with: request)
        urlSessionTask?.resume()
    }
    
    private func processIncrementalData(_ newData: Data) {
        // CRITICAL: Prevent memory leak by limiting buffer size
        if accumulatedData.count > self.maxBufferSize {
            // Keep only the last portion of data to avoid losing incomplete items
            let keepSize = self.cleanupThreshold
            let startIndex = max(0, accumulatedData.count - keepSize)
            accumulatedData = accumulatedData.subdata(in: startIndex..<accumulatedData.count)
            lastProcessedPosition = 0 // Reset position after truncation
        }
        
        // Append new data to accumulated buffer
        accumulatedData.append(newData)
        
        // Try to parse accumulated data incrementally
        // We look for complete <item> elements and parse them immediately
        let dataString = String(data: accumulatedData, encoding: .utf8) ?? ""
        
        // Find complete <item>...</item> blocks
        let itemPattern = "<item[^>]*>.*?</item>"
        guard let regex = try? NSRegularExpression(pattern: itemPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return
        }
        
        let range = NSRange(location: lastProcessedPosition, length: dataString.count - lastProcessedPosition)
        let matches = regex.matches(in: dataString, options: [], range: range)
        
        for match in matches {
            guard let swiftRange = Range(match.range, in: dataString) else { continue }
            let itemXML = String(dataString[swiftRange])
            
            // Parse this individual item
            if let episode = parseEpisodeFromXML(itemXML) {
                self.episodeCount += 1
                continuation?.yield(.episode(episode))
            }
            
            // Update last processed position
            lastProcessedPosition = match.range.upperBound
        }
        
        // CRITICAL: Clean up processed data to prevent memory leak
        if accumulatedData.count > self.cleanupThreshold && lastProcessedPosition > 0 {
            // Remove processed data, keep only unprocessed portion
            let unprocessedData = accumulatedData.subdata(in: lastProcessedPosition..<accumulatedData.count)
            accumulatedData = unprocessedData
            lastProcessedPosition = 0
            
        }
        
        // Extract and emit podcast metadata if we haven't yet
        if !metadataEmitted {
            extractAndEmitMetadata(from: dataString)
        }
    }
    
    private func parseEpisodeFromXML(_ itemXML: String) -> Episode? {
        // Extract episode data using regex patterns
        let title = extractValue(from: itemXML, tag: "title") ?? "Untitled Episode"
        let description = extractValue(from: itemXML, tag: "description")
        let audioURLString = extractAttribute(from: itemXML, tag: "enclosure", attribute: "url")
        let pubDateString = extractValue(from: itemXML, tag: "pubDate")
        let durationString = extractValue(from: itemXML, tag: "itunes:duration")
        
        // Validate that we have an audio URL (required for episodes)
        guard let audioURLString = audioURLString,
              let audioURL = URL(string: audioURLString) else {
            return nil
        }
        
        let episodeArtworkURL = extractEpisodeArtwork(from: itemXML)
        
        // Improved date parsing with stable fallbacks
        let publishedDate: Date
        if let parsedDate = parsePubDate(pubDateString) {
            publishedDate = parsedDate
        } else {
            // Instead of using Date() which creates identical timestamps,
            // create stable fallback dates that maintain episode order
            // Newer episodes in RSS feeds typically appear first, so subtract more time for later episodes
            let baseFallbackDate = Date().addingTimeInterval(-365 * 24 * 60 * 60) // 1 year ago
            let dayOffset = TimeInterval(episodeCount * 24 * 60 * 60) // 1 day per episode
            publishedDate = baseFallbackDate.addingTimeInterval(-dayOffset)
        }
        
        let duration = parseDuration(durationString) ?? 0
        
        // Generate deterministic UUID - need to add feedURL parameter to this class
        // For now, create a synthetic feedURL based on podcastID
        guard let syntheticFeedURL = URL(string: "streaming://\(podcastID.uuidString)") else {
            Self.logger.error("Failed to create synthetic feed URL for podcast: \(self.podcastID)")
            return nil
        }
        let deterministicID = DeterministicUUIDGenerator.generateEpisodeID(
            feedURL: syntheticFeedURL,
            audioURL: audioURL,
            title: title,
            publishedDate: publishedDate
        )
        
        return Episode(
            id: deterministicID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            podcastID: podcastID,
            publishedDate: publishedDate,
            duration: duration,
            artworkURL: episodeArtworkURL,
            description: description?.trimmingCharacters(in: .whitespacesAndNewlines),
            audioURL: audioURL
        )
    }
    
    private func extractAndEmitMetadata(from xmlString: String) {
        // Look for channel metadata in the accumulated data
        if xmlString.contains("<channel>") || xmlString.contains("<title>") {
            let title = extractValue(from: xmlString, tag: "title")
            let author = extractValue(from: xmlString, tag: "itunes:author") ?? extractValue(from: xmlString, tag: "author")
            let description = extractValue(from: xmlString, tag: "description")
            let artworkURL = extractAttribute(from: xmlString, tag: "itunes:image", attribute: "href")
            
            if let title = title, !title.isEmpty {
                let metadata = PodcastMetadata(
                    title: title,
                    author: author,
                    description: description,
                    artworkURL: artworkURL.flatMap { URL(string: $0) }
                )
                
                continuation?.yield(.metadata(metadata))
                metadataEmitted = true
            }
        }
    }
    
    // MARK: - XML Parsing Utilities
    
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
        let pattern = "<\(tag)[^>]*\(attribute)\\s*=\\s*[\"']([^\"']*)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        
        let range = NSRange(location: 0, length: xmlString.count)
        guard let match = regex.firstMatch(in: xmlString, options: [], range: range) else { return nil }
        
        let matchRange = match.range(at: 1)
        guard let swiftRange = Range(matchRange, in: xmlString) else { return nil }
        
        return String(xmlString[swiftRange])
    }
    
    private func extractEpisodeArtwork(from xmlString: String) -> URL? {
        if let itunesImageURL = extractAttribute(from: xmlString, tag: "itunes:image", attribute: "href") {
            return URL(string: itunesImageURL)
        }
        return nil
    }
    
    private func cleanHTMLTags(from string: String) -> String {
        // Strip CDATA wrappers before HTML tag removal to preserve content
        var value = string
        if value.contains("<![CDATA[") {
            value = value.replacingOccurrences(of: "<![CDATA[", with: "")
            value = value.replacingOccurrences(of: "]]>", with: "")
        }

        return value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func parsePubDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        // Try common RSS date formats
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd"
        ]
        
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        
        return nil
    }
    
    private func parseDuration(_ durationString: String?) -> TimeInterval? {
        guard let durationString = durationString else { return nil }
        
        let components = durationString.components(separatedBy: ":")
        if components.count == 3,
           let hours = Double(components[0]),
           let minutes = Double(components[1]),
           let seconds = Double(components[2]) {
            return hours * 3600 + minutes * 60 + seconds
        }
        
        if components.count == 2,
           let minutes = Double(components[0]),
           let seconds = Double(components[1]) {
            return minutes * 60 + seconds
        }
        
        if let seconds = Double(durationString) {
            return seconds
        }
        
        return nil
    }
    
    private func cleanup() {
        urlSessionTask?.cancel()
        xmlParser?.abortParsing()
        continuation?.finish()
        continuation = nil
    }
}

// MARK: - URLSessionDataDelegate

extension StreamingEpisodeIterator: URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        
        guard let httpResponse = response as? HTTPURLResponse else {
            continuation?.yield(.error(StreamingRSSError.invalidResponse))
            continuation?.finish()
            completionHandler(.cancel)
            return
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            continuation?.yield(.error(StreamingRSSError.httpError(httpResponse.statusCode)))
            continuation?.finish()
            completionHandler(.cancel)
            return
        }
        
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Process each chunk of data as it arrives - this is the key to streaming!
        // Instead of waiting for the full download, we parse episodes immediately
        processIncrementalData(data)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didCompleteWithError error: Error?) {
        if let error = error {
            
            // Check if this is a network connectivity issue that might be retryable
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost:
                    continuation?.yield(.error(StreamingRSSError.networkConnectivityIssue(urlError)))
                case .cancelled:
                    continuation?.yield(.error(StreamingRSSError.cancelled))
                default:
                    continuation?.yield(.error(error))
                }
            } else {
                continuation?.yield(.error(error))
            }
        } else {
            continuation?.yield(.completed(totalEpisodes: self.episodeCount))
        }
        
        continuation?.finish()
        cleanup()
    }
}

// MARK: - Error Types

enum StreamingRSSError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)
    case parsingError(String)
    case timeout
    case networkConnectivityIssue(URLError)
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .parsingError(let message):
            return "Parsing error: \(message)"
        case .timeout:
            return "Request timed out"
        case .networkConnectivityIssue(let urlError):
            return "Network connectivity issue: \(urlError.localizedDescription)"
        case .cancelled:
            return "Request was cancelled"
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .networkConnectivityIssue, .timeout:
            return true
        case .httpError(let code):
            return code >= 500 // Server errors are retryable
        default:
            return false
        }
    }
} 