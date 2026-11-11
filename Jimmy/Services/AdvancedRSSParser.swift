import Foundation
import OSLog

/// Advanced RSS Parser with memory management, error recovery, and intelligent parsing
final class AdvancedRSSParser: NSObject {
    private let logger = Logger(subsystem: "Jimmy.AdvancedParser", category: "RSSParser")
    
    // MARK: - Configuration
    private struct Config {
        static let maxMemoryUsage: Int64 = 100 * 1024 * 1024 // 100MB
        static let maxEpisodes = 10000
        static let parsingTimeout: TimeInterval = 120.0
        static let maxRetries = 3
        static let chunkSize = 64 * 1024 // 64KB chunks
    }
    
    // MARK: - Memory Management
    private var currentMemoryUsage: Int64 = 0
    private let memoryMonitor = RSSMemoryMonitor()
    
    override init() {
        super.init()
        logger.info("🧠 Advanced RSS Parser initialized")
    }
    
    // MARK: - Public API
    
    /// Parse RSS data with advanced memory management and error recovery
    func parse(
        data: Data,
        feedURL: URL,
        memoryLimit: Int64 = Config.maxMemoryUsage
    ) async throws -> ([Episode], ShowMetadata) {
        
        logger.info("📡 Parsing RSS feed: \(feedURL) (\(self.formatBytes(Int64(data.count))))")
        
        // Memory check
        guard data.count <= memoryLimit else {
            throw ParsingError.dataTooLarge(size: Int64(data.count), limit: memoryLimit)
        }
        
        // Validate XML structure
        try validateXMLStructure(data)
        
        // Choose parsing strategy based on data size
        if data.count > 10 * 1024 * 1024 { // 10MB
            return try await parseWithStreaming(data: data, feedURL: feedURL, memoryLimit: memoryLimit)
        } else {
            return try await parseWithDOM(data: data, feedURL: feedURL)
        }
    }
    
    // MARK: - DOM-based Parsing (for smaller feeds)
    
    private func parseWithDOM(data: Data, feedURL: URL) async throws -> ([Episode], ShowMetadata) {
        return try await withTimeout(Config.parsingTimeout) {
            let parser = DOMRSSParser(feedURL: feedURL)
            return try await parser.parse(data: data)
        }
    }
    
    // MARK: - Streaming Parsing (for larger feeds)
    
    private func parseWithStreaming(
        data: Data,
        feedURL: URL,
        memoryLimit: Int64
    ) async throws -> ([Episode], ShowMetadata) {
        
        logger.info("🌊 Using streaming parser for large feed")
        
        let streamingParser = MemoryEfficientStreamingParser(
            feedURL: feedURL,
            podcastID: DeterministicUUIDGenerator.generatePodcastID(from: feedURL),
            maxMemoryUsage: memoryLimit
        )
        
        var episodes: [Episode] = []
        var metadata: ShowMetadata?
        
        // Process data in chunks to manage memory
        let chunkSize = Config.chunkSize
        var offset = 0
        
        while offset < data.count {
            let endOffset = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset..<endOffset)
            
            // Process chunk
            for try await result in streamingParser.processChunk(chunk, isLast: endOffset == data.count) {
                switch result {
                case .episode(let episode):
                    episodes.append(episode)
                    
                    // Memory management
                    if episodes.count > Config.maxEpisodes {
                        logger.warning("⚠️ Reached maximum episode limit, truncating")
                        break
                    }
                    
                case .metadata(let meta):
                    if metadata == nil {
                        metadata = ShowMetadata(
                            title: meta.title,
                            author: meta.author,
                            description: meta.description,
                            artworkURL: meta.artworkURL,
                            language: nil,
                            categories: []
                        )
                    }
                    
                case .error(let error):
                    logger.warning("⚠️ Parsing error in chunk: \(error.localizedDescription)")
                    
                case .completed:
                    break
                }
            }
            
            offset = endOffset
            
            // Memory pressure check
            if memoryMonitor.getCurrentUsage() > memoryLimit {
                logger.warning("⚠️ Memory limit reached, stopping parsing")
                break
            }
        }
        
        return (episodes, metadata ?? ShowMetadata(title: "Unknown Podcast", author: nil, description: nil, artworkURL: nil, language: nil, categories: []))
    }
    
    // MARK: - XML Validation
    
    private func validateXMLStructure(_ data: Data) throws {
        // Quick validation to ensure we have valid XML
        guard let xmlString = String(data: data.prefix(1000), encoding: .utf8) else {
            throw ParsingError.invalidEncoding
        }
        
        // Check for XML declaration or root elements
        let hasXMLDeclaration = xmlString.contains("<?xml")
        let hasRSSRoot = xmlString.contains("<rss") || xmlString.contains("<feed")
        let hasChannelOrFeed = xmlString.contains("<channel") || xmlString.contains("<feed")
        
        guard hasXMLDeclaration || hasRSSRoot || hasChannelOrFeed else {
            throw ParsingError.invalidXMLStructure
        }
        
        // Check for common encoding issues
        if xmlString.contains("�") {
            logger.warning("⚠️ Detected encoding issues in XML")
        }
    }
    
    // MARK: - Utility Methods
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - DOM RSS Parser

private class DOMRSSParser: NSObject, XMLParserDelegate {
    private let feedURL: URL
    private let podcastID: UUID
    
    private var episodes: [Episode] = []
    private var metadata: ShowMetadata?
    
    // Parsing state
    private var currentElement = ""
    private var isParsingItem = false
    private var isParsingChannel = false
    private var characterBuffer = ""
    
    // Current episode being parsed
    private var currentEpisode: EpisodeBuilder?
    
    // Channel metadata
    private var channelTitle = ""
    private var channelAuthor = ""
    private var channelDescription = ""
    private var channelArtworkURL: URL?
    private var channelLanguage = ""
    private var channelCategories: [String] = []
    
    // Error handling
    private var continuation: CheckedContinuation<([Episode], ShowMetadata), Error>?
    
    init(feedURL: URL) {
        self.feedURL = feedURL
        self.podcastID = DeterministicUUIDGenerator.generatePodcastID(from: feedURL)
        super.init()
    }
    
    func parse(data: Data) async throws -> ([Episode], ShowMetadata) {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            let parser = XMLParser(data: data)
            parser.delegate = self
            parser.shouldProcessNamespaces = true
            parser.shouldReportNamespacePrefixes = true
            
            if !parser.parse() {
                let error = parser.parserError ?? ParsingError.unknownParsingError
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - XMLParserDelegate
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        
        currentElement = elementName.lowercased()
        characterBuffer = ""
        
        switch currentElement {
        case "channel", "feed":
            isParsingChannel = true
            
        case "item", "entry":
            isParsingItem = true
            currentEpisode = EpisodeBuilder(podcastID: podcastID, feedURL: feedURL)
            
        case "enclosure":
            if isParsingItem, let episode = currentEpisode {
                if let url = attributeDict["url"], let audioURL = URL(string: url) {
                    episode.audioURL = audioURL
                }
            }
            
        case "itunes:image", "image":
            if let href = attributeDict["href"] ?? attributeDict["url"] {
                if isParsingItem {
                    currentEpisode?.artworkURL = URL(string: href)
                } else if isParsingChannel {
                    channelArtworkURL = URL(string: href)
                }
            }
            
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        characterBuffer += string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            characterBuffer = string // CDATA replaces existing content
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        
        let element = elementName.lowercased()
        let content = characterBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if isParsingItem, let episode = currentEpisode {
            // Episode elements
            switch element {
            case "title":
                episode.title = content
            case "description", "summary", "content":
                episode.description = content
            case "pubdate", "published":
                episode.publishedDate = parseDate(content)
            case "itunes:duration", "duration":
                episode.duration = parseDuration(content)
            case "link":
                if episode.audioURL == nil, let url = URL(string: content) {
                    episode.audioURL = url
                }
            case "item", "entry":
                // End of episode
                if let builtEpisode = episode.build() {
                    episodes.append(builtEpisode)
                }
                currentEpisode = nil
                isParsingItem = false
            default:
                break
            }
        } else if isParsingChannel {
            // Channel elements
            switch element {
            case "title":
                channelTitle = content
            case "itunes:author", "author":
                channelAuthor = content
            case "description", "summary":
                channelDescription = content
            case "channel", "feed":
                isParsingChannel = false
            default:
                break
            }
        }
        
        characterBuffer = ""
    }
    
    func parserDidEndDocument(_ parser: XMLParser) {
        let finalMetadata = ShowMetadata(
            title: channelTitle.isEmpty ? nil : channelTitle,
            author: channelAuthor.isEmpty ? nil : channelAuthor,
            description: channelDescription.isEmpty ? nil : channelDescription,
            artworkURL: channelArtworkURL,
            language: channelLanguage.isEmpty ? nil : channelLanguage,
            categories: channelCategories
        )
        
        continuation?.resume(returning: (episodes, finalMetadata))
    }
    
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        continuation?.resume(throwing: parseError)
    }
    
    // MARK: - Parsing Utilities
    
    private func parseDate(_ dateString: String) -> Date? {
        let formatters = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss"
        ]
        
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        
        return nil
    }
    
    private func parseDuration(_ durationString: String) -> TimeInterval? {
        let trimmed = durationString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle HH:MM:SS format
        if trimmed.contains(":") {
            let components = trimmed.components(separatedBy: ":")
            var totalSeconds: TimeInterval = 0
            
            for (index, component) in components.reversed().enumerated() {
                if let value = Double(component) {
                    totalSeconds += value * pow(60, Double(index))
                }
            }
            
            return totalSeconds > 0 ? totalSeconds : nil
        }
        
        // Handle seconds as number
        return Double(trimmed)
    }
}

// MARK: - Episode Builder

private class EpisodeBuilder {
    let podcastID: UUID
    let feedURL: URL
    
    var title: String = ""
    var description: String = ""
    var audioURL: URL?
    var artworkURL: URL?
    var publishedDate: Date?
    var duration: TimeInterval?
    
    init(podcastID: UUID, feedURL: URL) {
        self.podcastID = podcastID
        self.feedURL = feedURL
    }
    
    func build() -> Episode? {
        guard !title.isEmpty, let audioURL = audioURL else {
            return nil
        }
        
        let episodeID = DeterministicUUIDGenerator.generateEpisodeID(
            feedURL: feedURL,
            audioURL: audioURL,
            title: title,
            publishedDate: publishedDate ?? Date()
        )
        
        return Episode(
            id: episodeID,
            title: title,
            podcastID: podcastID,
            publishedDate: publishedDate ?? Date(),
            duration: duration,
            artworkURL: artworkURL,
            description: description.isEmpty ? nil : description,
            audioURL: audioURL
        )
    }
}

// MARK: - Memory Monitor

class RSSMemoryMonitor {
    func getCurrentUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return kerr == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}

// MARK: - Timeout Wrapper

private func withTimeout<T>(
    _ timeout: TimeInterval,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw ParsingError.timeout
        }
        
        guard let result = try await group.next() else {
            throw ParsingError.timeout
        }
        
        group.cancelAll()
        return result
    }
}

// MARK: - Error Types

enum ParsingError: Error, LocalizedError {
    case dataTooLarge(size: Int64, limit: Int64)
    case invalidEncoding
    case invalidXMLStructure
    case timeout
    case unknownParsingError
    case memoryLimitExceeded
    
    var errorDescription: String? {
        switch self {
        case .dataTooLarge(let size, let limit):
            return "RSS feed too large: \(size) bytes (limit: \(limit) bytes)"
        case .invalidEncoding:
            return "Invalid text encoding in RSS feed"
        case .invalidXMLStructure:
            return "Invalid XML structure in RSS feed"
        case .timeout:
            return "RSS parsing timed out"
        case .unknownParsingError:
            return "Unknown RSS parsing error"
        case .memoryLimitExceeded:
            return "Memory limit exceeded during parsing"
        }
    }
}
