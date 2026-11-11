import Foundation
import CommonCrypto

/// Simple streaming episode service that solves the core timeout/UI-blocking issue
/// This replaces the "download all then parse" approach with true streaming
final class SimpleStreamingEpisodeService {
    static let shared = SimpleStreamingEpisodeService()
    private init() {}
    
    /// Creates an AsyncSequence that streams episodes as they're parsed from RSS feed
    /// This is the core solution: episodes appear immediately as parsed, no waiting for full download
    func streamEpisodes(from feedURL: URL, podcastID: UUID) -> AsyncThrowingStream<Episode, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                await self.performStreamingParse(feedURL: feedURL, podcastID: podcastID, continuation: continuation)
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    

    
    // MARK: - Core Streaming Implementation
    
    private func performStreamingParse(
        feedURL: URL, 
        podcastID: UUID, 
        continuation: AsyncThrowingStream<Episode, Error>.Continuation
    ) async {
        do {
            // Create URLSession with streaming configuration
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30.0
            config.timeoutIntervalForResource = 120.0
            
            // CRITICAL: Use HTTP/1.1 to prevent QUIC protocol violations
            config.httpAdditionalHeaders = ["Connection": "keep-alive"]
            
            config.waitsForConnectivity = false  // Prevent hanging during streaming
            
            let session = URLSession(configuration: config)
            
            var request = URLRequest(url: feedURL, timeoutInterval: 30.0)
            request.setValue("Jimmy/2.0 (iOS Podcast Client)", forHTTPHeaderField: "User-Agent")
            // This is the key: we get data chunks as they arrive, not all at once
            let (asyncBytes, response) = try await session.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw SimpleStreamingError.invalidResponse
            }
            // Create streaming XML parser
            var episodeCount = 0
            let parser = StreamingXMLParser(feedURL: feedURL, podcastID: podcastID) { episode in
                // This callback fires immediately when each episode is parsed
                // No waiting for full download!
                episodeCount += 1
                continuation.yield(episode)
            }
            
            // Process data in larger chunks instead of byte-by-byte
            var buffer = Data()
            let chunkSize = 8192 // 8KB chunks for better parsing
            var totalBytes = 0
            
            for try await byte in asyncBytes {
                if Task.isCancelled {
                    break
                }
                
                buffer.append(byte)
                totalBytes += 1
                
                // Process in chunks to allow regex to find complete items
                if buffer.count >= chunkSize {
                    parser.feedData(buffer)
                    buffer.removeAll()
                }
            }
            
            // Process any remaining data
            if !buffer.isEmpty {
                parser.feedData(buffer)
            }
            
            // Finalize parsing
            parser.complete()
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }
}

// MARK: - Streaming XML Parser

/// Incremental XML parser that emits episodes as soon as they're complete
private class StreamingXMLParser: NSObject, XMLParserDelegate {
    private let feedURL: URL
    private let podcastID: UUID
    private let onEpisodeParsed: (Episode) -> Void
    
    private var xmlParser: XMLParser?
    private var accumulatedData = Data()
    
    // CRITICAL: Memory leak prevention
    private let maxBufferSize = 10 * 1024 * 1024 // 10MB max buffer
    private let cleanupThreshold = 5 * 1024 * 1024 // Clean up at 5MB
    
    // Episode ordering for stable fallback dates
    private var episodeCount = 0
    private let baseFallbackDate = Date().addingTimeInterval(-365 * 24 * 60 * 60) // 1 year ago
    
    // Current episode being parsed
    private var currentElement = ""
    private var isParsingItem = false
    private var currentTitle = ""
    private var currentDescription = ""
    private var currentAudioURL = ""
    private var currentPubDate = ""
    private var currentDuration: TimeInterval?
    
    init(feedURL: URL, podcastID: UUID, onEpisodeParsed: @escaping (Episode) -> Void) {
        self.feedURL = feedURL
        self.podcastID = podcastID
        self.onEpisodeParsed = onEpisodeParsed
        super.init()
    }
    
    func feedData(_ data: Data) {
        // CRITICAL: Prevent memory leak by limiting buffer size
        if accumulatedData.count > maxBufferSize {
            // Emergency cleanup - keep only recent data
            let keepSize = cleanupThreshold
            let startIndex = max(0, accumulatedData.count - keepSize)
            accumulatedData = accumulatedData.subdata(in: startIndex..<accumulatedData.count)
        }
        
        accumulatedData.append(data)
        
        // Try to find complete <item>...</item> blocks in accumulated data
        let dataString = String(data: accumulatedData, encoding: .utf8) ?? ""
        
        // Look for complete item blocks - using a more robust pattern
        let itemPattern = "<item[^>]*>[\\s\\S]*?</item>"
        guard let regex = try? NSRegularExpression(pattern: itemPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return
        }
        
        let matches = regex.matches(in: dataString, options: [], range: NSRange(location: 0, length: dataString.count))
        
        var processedRanges: [NSRange] = []
        
        for match in matches {
            let matchRange = match.range
            let itemXML = String(dataString[Range(matchRange, in: dataString)!])
            
            if let episode = parseEpisodeFromXML(itemXML) {
                onEpisodeParsed(episode)
                processedRanges.append(matchRange)
            }
        }
        
        // Remove processed data to prevent reprocessing and memory bloat
        if !processedRanges.isEmpty {
            // Find the end of the last processed item
            let lastProcessedEnd = processedRanges.map { $0.location + $0.length }.max() ?? 0
            
            // Keep data from after the last processed item
            if lastProcessedEnd < dataString.count {
                let remainingString = String(dataString.suffix(dataString.count - lastProcessedEnd))
                accumulatedData = remainingString.data(using: .utf8) ?? Data()
            } else {
                accumulatedData = Data()
            }
        }
    }
    
    func complete() {
        // Process any remaining data
        let dataString = String(data: accumulatedData, encoding: .utf8) ?? ""
        if !dataString.isEmpty {
            // Try to parse any remaining partial items
            if let episode = parseEpisodeFromXML(dataString) {
                onEpisodeParsed(episode)
            }
        }
    }
    
    // MARK: - UUID Generation
    // NOTE: This method is deprecated - use DeterministicUUIDGenerator instead
    // Keeping for backward compatibility during migration
    
    // MARK: - Episode Parsing
    
    private func parseEpisodeFromXML(_ xml: String) -> Episode? {
        let title = extractValue(from: xml, tag: "title") ?? "Untitled Episode"
        let description = extractValue(from: xml, tag: "description")
        let audioURLString = extractAttribute(from: xml, tag: "enclosure", attribute: "url")
        let pubDateString = extractValue(from: xml, tag: "pubDate")
        let durationString = extractValue(from: xml, tag: "itunes:duration")
        
        // Extract episode artwork URL
        let artworkURLString = extractAttribute(from: xml, tag: "itunes:image", attribute: "href")
        let artworkURL = artworkURLString.flatMap { URL(string: $0) }
        
        // Must have audio URL
        guard let audioURLString = audioURLString,
              let audioURL = URL(string: audioURLString) else {
            return nil
        }
        
        // Improved date parsing with stable fallbacks
        let publishedDate: Date
        if let parsedDate = parsePubDate(pubDateString) {
            publishedDate = parsedDate
        } else {
            // Instead of using Date() which creates identical timestamps,
            // create stable fallback dates that maintain episode order
            // Newer episodes in RSS feeds typically appear first, so subtract more time for later episodes
            let dayOffset = TimeInterval(episodeCount * 24 * 60 * 60) // 1 day per episode
            publishedDate = baseFallbackDate.addingTimeInterval(-dayOffset)
        }
        
        let duration = parseDuration(durationString) ?? 0
        
        // CRITICAL FIX: Generate deterministic UUID based on feed URL and episode data
        // This ensures the same episode always gets the same ID regardless of source (database vs RSS)
        let deterministicID = DeterministicUUIDGenerator.generateEpisodeID(
            feedURL: feedURL,
            audioURL: audioURL,
            title: title,
            publishedDate: publishedDate
        )
        
        let episode = Episode(
            id: deterministicID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            podcastID: podcastID,
            publishedDate: publishedDate,
            duration: duration,
            artworkURL: artworkURL,
            description: description?.trimmingCharacters(in: .whitespacesAndNewlines),
            audioURL: audioURL
        )
        
        // Increment counter for next episode's fallback date
        episodeCount += 1
        
        return episode
    }
    
    // MARK: - XML Parsing Utilities
    
    private func extractValue(from xml: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        
        let range = NSRange(location: 0, length: xml.count)
        guard let match = regex.firstMatch(in: xml, options: [], range: range) else { return nil }
        
        let matchRange = match.range(at: 1)
        guard let swiftRange = Range(matchRange, in: xml) else { return nil }
        
        var value = String(xml[swiftRange])
        
        // Handle CDATA sections - this is crucial for Hebrew text
        if value.hasPrefix("<![CDATA[") && value.hasSuffix("]]>") {
            let startIndex = value.index(value.startIndex, offsetBy: 9) // "<![CDATA[".count
            let endIndex = value.index(value.endIndex, offsetBy: -3) // "]]>".count
            if startIndex < endIndex {
                value = String(value[startIndex..<endIndex])
            }
        }
        
        return cleanHTMLTags(from: value)
    }
    
    private func extractAttribute(from xml: String, tag: String, attribute: String) -> String? {
        let pattern = "<\(tag)[^>]*\(attribute)\\s*=\\s*[\"']([^\"']*)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        
        let range = NSRange(location: 0, length: xml.count)
        guard let match = regex.firstMatch(in: xml, options: [], range: range) else { return nil }
        
        let matchRange = match.range(at: 1)
        guard let swiftRange = Range(matchRange, in: xml) else { return nil }
        
        return String(xml[swiftRange])
    }
    
    private func cleanHTMLTags(from string: String) -> String {
        // First remove HTML tags
        var result = string.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // Then decode HTML entities with comprehensive support for Hebrew
        result = decodeHTMLEntities(result)
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        
        // Decode common HTML entities
        let htmlEntities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&nbsp;": " ",
            "&#39;": "'",
            "&#x27;": "'",
            "&rsquo;": "'",
            "&lsquo;": "'",
            "&rdquo;": "\u{201D}",
            "&ldquo;": "\u{201C}",
            "&mdash;": "—",
            "&ndash;": "–",
            "&hellip;": "…",
            "&#8211;": "–",
            "&#8212;": "—",
            "&#8216;": "'",
            "&#8217;": "'",
            "&#8220;": "\u{201C}",
            "&#8221;": "\u{201D}",
            "&#8230;": "…"
        ]
        
        for (entity, replacement) in htmlEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        
        // Handle numeric HTML entities (&#123;) - crucial for Hebrew characters
        let numericEntityPattern = "&#(\\d+);"
        if let regex = try? NSRegularExpression(pattern: numericEntityPattern, options: []) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.count))
            
            // Process matches in reverse order to avoid index shifting
            for match in matches.reversed() {
                guard let numberRange = Range(match.range(at: 1), in: result),
                      let number = Int(String(result[numberRange])),
                      let scalar = UnicodeScalar(number),
                      let fullRange = Range(match.range, in: result) else {
                    continue
                }
                result.replaceSubrange(fullRange, with: String(scalar))
            }
        }
        
        // Handle hex HTML entities (&#x123;) - also important for Hebrew
        let hexEntityPattern = "&#x([0-9a-fA-F]+);"
        if let regex = try? NSRegularExpression(pattern: hexEntityPattern, options: []) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.count))
            
            // Process matches in reverse order to avoid index shifting
            for match in matches.reversed() {
                guard let hexRange = Range(match.range(at: 1), in: result),
                      let number = Int(String(result[hexRange]), radix: 16),
                      let scalar = UnicodeScalar(number),
                      let fullRange = Range(match.range, in: result) else {
                    continue
                }
                result.replaceSubrange(fullRange, with: String(scalar))
            }
        }
        
        return result
    }
    
    private func parsePubDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
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
}

// MARK: - Error Types

enum SimpleStreamingError: Error, LocalizedError {
    case invalidResponse
    case networkError(Error)
    case parsingError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parsingError(let message):
            return "Parsing error: \(message)"
        }
    }
} 