import Foundation
import OSLog

/// Memory-efficient streaming parser for large RSS feeds
/// Processes data incrementally to prevent memory issues with massive feeds
final class MemoryEfficientStreamingParser {
    private let logger = Logger(subsystem: "Jimmy.StreamingParser", category: "MemoryEfficient")
    
    // MARK: - Configuration
    private struct Config {
        static let bufferSize = 64 * 1024 // 64KB buffer
        static let maxItemBuffer = 1024 * 1024 // 1MB max per item
        static let memoryCheckInterval = 100 // Check memory every 100 items
    }
    
    // MARK: - Properties
    private let feedURL: URL
    private let podcastID: UUID
    private let maxMemoryUsage: Int64
    
    // MARK: - Parsing State
    private var xmlBuffer = Data()
    private var currentItem = Data()
    private var isInItem = false
    private var itemDepth = 0
    private var episodeCount = 0
    
    // MARK: - Metadata
    private var channelMetadata: PodcastMetadata?
    private var hasEmittedMetadata = false
    
    // MARK: - Memory Management
    private var lastMemoryCheck: Int64 = 0
    
    init(feedURL: URL, podcastID: UUID, maxMemoryUsage: Int64) {
        self.feedURL = feedURL
        self.podcastID = podcastID
        self.maxMemoryUsage = maxMemoryUsage
        
        logger.info("🌊 Memory-efficient streaming parser initialized for \(feedURL)")
    }
    
    // MARK: - Public API
    
    /// Stream episodes from RSS feed data
    func streamEpisodes() -> AsyncThrowingStream<StreamingEpisodeResult, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // This would typically be called with network data chunks
                    // For now, we'll simulate streaming by processing the full feed
                    let (data, _, _) = try await UnifiedNetworkService.shared.fetchRSSFeed(from: feedURL, etag: nil, lastModified: nil)
                    
                    // Process in chunks
                    await processDataStream(data, continuation: continuation)
                    
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Process a chunk of RSS data
    func processChunk(_ chunk: Data, isLast: Bool) -> AsyncThrowingStream<StreamingEpisodeResult, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                await processDataChunk(chunk, isLast: isLast, continuation: continuation)
                if isLast {
                    continuation.finish()
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func processDataStream(_ data: Data, continuation: AsyncThrowingStream<StreamingEpisodeResult, Error>.Continuation) async {
        let chunkSize = Config.bufferSize
        var offset = 0
        
        while offset < data.count {
            let endOffset = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset..<endOffset)
            
            await processDataChunk(chunk, isLast: endOffset == data.count, continuation: continuation)
            
            offset = endOffset
            
            // Memory pressure check
            if episodeCount % Config.memoryCheckInterval == 0 {
                let currentMemory = getCurrentMemoryUsage()
                if currentMemory > maxMemoryUsage {
                    logger.warning("⚠️ Memory limit exceeded: \(self.formatBytes(currentMemory))")
                    continuation.yield(.error(StreamingError.memoryLimitExceeded))
                    return
                }
            }
        }
    }
    
    private func processDataChunk(
        _ chunk: Data,
        isLast: Bool,
        continuation: AsyncThrowingStream<StreamingEpisodeResult, Error>.Continuation
    ) async {
        
        // Append to buffer
        xmlBuffer.append(chunk)
        
        // Process complete items from buffer
        await processBufferForItems(continuation: continuation)
        
        // Extract metadata if we haven't yet
        if !hasEmittedMetadata {
            await extractMetadata(continuation: continuation)
        }
        
        // Clean up buffer to prevent memory growth
        await cleanupBuffer()
        
        if isLast {
            // Process any remaining partial item
            await processRemainingData(continuation: continuation)
            
            // Emit completion
            continuation.yield(.completed(totalEpisodes: episodeCount))
        }
    }
    
    private func processBufferForItems(continuation: AsyncThrowingStream<StreamingEpisodeResult, Error>.Continuation) async {
        let xmlString = String(data: xmlBuffer, encoding: .utf8) ?? ""
        
        // Find complete <item>...</item> blocks
        let itemPattern = "<item[^>]*>.*?</item>"
        
        do {
            let regex = try NSRegularExpression(pattern: itemPattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
            let matches = regex.matches(in: xmlString, options: [], range: NSRange(location: 0, length: xmlString.count))
            
            var processedLength = 0
            
            for match in matches {
                guard let swiftRange = Range(match.range, in: xmlString) else { continue }
                let itemXML = String(xmlString[swiftRange])
                
                // Parse this individual item
                if let episode = await parseEpisodeFromXML(itemXML) {
                    episodeCount += 1
                    continuation.yield(.episode(episode))
                    
                    // logger.debug("📦 Parsed episode \(self.episodeCount): \(episode.title)")
                }
                
                processedLength = match.range.upperBound
            }
            
            // Remove processed data from buffer
            if processedLength > 0 {
                let remainingData = xmlString.suffix(xmlString.count - processedLength)
                xmlBuffer = Data(remainingData.utf8)
            }
            
        } catch {
            logger.error("❌ Regex error in item processing: \(error)")
            continuation.yield(.error(error))
        }
    }
    
    private func extractMetadata(continuation: AsyncThrowingStream<StreamingEpisodeResult, Error>.Continuation) async {
        let xmlString = String(data: xmlBuffer, encoding: .utf8) ?? ""
        
        // Look for channel metadata
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
                
                channelMetadata = metadata
                continuation.yield(.metadata(metadata))
                hasEmittedMetadata = true
                
                logger.debug("📊 Extracted metadata: \(title)")
            }
        }
    }
    
    private func parseEpisodeFromXML(_ itemXML: String) async -> Episode? {
        // Extract episode data using optimized parsing
        guard let title = extractValue(from: itemXML, tag: "title"), !title.isEmpty else {
            return nil
        }
        
        let description = extractValue(from: itemXML, tag: "description")
        let audioURLString = extractAttribute(from: itemXML, tag: "enclosure", attribute: "url")
        let pubDateString = extractValue(from: itemXML, tag: "pubDate")
        let durationString = extractValue(from: itemXML, tag: "itunes:duration")
        
        // Validate audio URL
        guard let audioURLString = audioURLString,
              let audioURL = URL(string: audioURLString) else {
            return nil
        }
        
        let episodeArtworkURL = extractEpisodeArtwork(from: itemXML)
        
        // Parse date with fallback
        let publishedDate: Date
        if let parsedDate = parsePubDate(pubDateString) {
            publishedDate = parsedDate
        } else {
            // Stable fallback based on episode order
            let dayOffset = TimeInterval(episodeCount * 24 * 60 * 60)
            publishedDate = Date().addingTimeInterval(-365 * 24 * 60 * 60 - dayOffset)
        }
        
        let duration = parseDuration(durationString) ?? 0
        
        // Generate deterministic ID
        let episodeID = DeterministicUUIDGenerator.generateEpisodeID(
            feedURL: feedURL,
            audioURL: audioURL,
            title: title,
            publishedDate: publishedDate
        )
        
        return Episode(
            id: episodeID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            podcastID: podcastID,
            publishedDate: publishedDate,
            duration: duration,
            artworkURL: episodeArtworkURL,
            description: description?.trimmingCharacters(in: .whitespacesAndNewlines),
            audioURL: audioURL
        )
    }
    
    private func processRemainingData(continuation: AsyncThrowingStream<StreamingEpisodeResult, Error>.Continuation) async {
        // Process any incomplete items in the buffer
        let xmlString = String(data: xmlBuffer, encoding: .utf8) ?? ""
        
        if xmlString.contains("<item") && !xmlString.contains("</item>") {
            logger.debug("📝 Processing incomplete item at end of stream")
            // Try to parse incomplete item - this is best effort
        }
    }
    
    private func cleanupBuffer() async {
        // Prevent buffer from growing too large
        if xmlBuffer.count > Config.maxItemBuffer * 2 {
            // Keep only the last portion to avoid losing incomplete items
            let keepSize = Config.maxItemBuffer
            let startIndex = max(0, xmlBuffer.count - keepSize)
            xmlBuffer = xmlBuffer.subdata(in: startIndex..<xmlBuffer.count)
            
            logger.debug("🧹 Cleaned up XML buffer, kept \(self.formatBytes(Int64(self.xmlBuffer.count)))")
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
        return string
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
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
    
    // MARK: - Memory Management
    
    private func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return kerr == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Error Types

enum StreamingError: Error, LocalizedError {
    case memoryLimitExceeded
    case parsingError(String)
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .memoryLimitExceeded:
            return "Memory limit exceeded during streaming"
        case .parsingError(let message):
            return "Streaming parsing error: \(message)"
        case .invalidData:
            return "Invalid data received during streaming"
        }
    }
}
