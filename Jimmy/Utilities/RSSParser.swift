import Foundation
import OSLog

/// A memory-efficient, stream-based RSS parser that uses `XMLParserDelegate`.
/// This parser is designed to handle large RSS feeds without consuming excessive memory
/// by processing the XML stream node by node instead of loading the entire document at once.
class RSSParser: NSObject, XMLParserDelegate {
    
    // MARK: - Private Properties
    private var episodes: [Episode] = []
    private var podcastID: UUID
    
    // State machine for parsing
    private var currentElementName: String = ""
    private var isParsingItem: Bool = false
    private var isParsingChannel: Bool = false
    
    // Episode properties under construction
    private var currentTitle: String = ""
    private var currentAudioURL: String = ""
    private var currentDescription: String = ""
    private var currentPubDate: String = ""
    private var currentEpisodeArtworkURL: String = ""
    
    // Podcast metadata
    private var podcastTitle: String = ""
    private var podcastAuthor: String = ""
    private var podcastDescription: String = ""
    private var podcastArtworkURL: String = ""
    
    // Asynchronous parsing control
    private var parser: XMLParser!
    private var continuation: CheckedContinuation<([Episode], PodcastMetadata), Error>?
    
    // Progressive parsing support
    private var progressiveCallback: ((Episode) -> Void)?
    private var metadataCallback: ((PodcastMetadata) -> Void)?
    private var progressiveCompletion: ((Result<([Episode], PodcastMetadata), Error>) -> Void)?
    private var episodeCount: Int = 0
    
    private let logger = Logger(subsystem: "com.jimmy.app", category: "RSSParser")
    
    // MARK: - Initialization
    
    init(podcastID: UUID) {
        self.podcastID = podcastID
        super.init()
    }
    
    // MARK: - Public Interface
    
    /// Parses episodes progressively, calling the callback for each episode as it's parsed
    /// - Parameters:
    ///   - url: The URL of the RSS feed
    ///   - episodeCallback: Called for each episode as it's parsed
    ///   - metadataCallback: Called when podcast metadata is available
    ///   - completion: Called when parsing is complete with all episodes and metadata
    func parseProgressively(from url: URL, 
                           episodeCallback: @escaping (Episode) -> Void,
                           metadataCallback: @escaping (PodcastMetadata) -> Void,
                           completion: @escaping (Result<([Episode], PodcastMetadata), Error>) -> Void) {
        
        self.progressiveCallback = episodeCallback
        self.metadataCallback = metadataCallback
        self.episodeCount = 0
        self.episodes = []
        
        // Reset podcast metadata
        self.podcastTitle = ""
        self.podcastAuthor = ""
        self.podcastDescription = ""
        self.podcastArtworkURL = ""
        
        logger.info("🚀 Starting progressive parsing for podcast ID: \(self.podcastID)")
        
        // Use OptimizedNetworkManager for better network handling
        Task {
            do {
                let data = try await OptimizedNetworkManager.shared.fetchData(url: url)
                
                guard !data.isEmpty else {
                    self.logger.error("❌ No data received from RSS feed: \(url)")
                    let error = NSError(domain: "RSSParser", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "No data received from podcast feed",
                        NSLocalizedRecoverySuggestionErrorKey: "The podcast feed may be temporarily unavailable or the URL may be incorrect."
                    ])
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                    return
                }
                
                // Debug: Log the first part of the received data
                if let dataString = String(data: data, encoding: .utf8) {
                    let preview = String(dataString.prefix(500))
                    self.logger.info("📄 Received data preview: \(preview)")
                    
                    // Check if it looks like XML
                    if dataString.contains("<?xml") || dataString.contains("<rss") || dataString.contains("<feed") {
                        self.logger.info("✅ Data appears to be XML format")
                    } else {
                        self.logger.warning("⚠️ Data does not appear to be XML format")
                    }
                }
                
                // Parse progressively
                self.parseDataProgressively(data: data, completion: completion)
                
            } catch {
                self.logger.error("❌ Network error fetching RSS feed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Parses episodes from RSS data for FetchWorker compatibility
    /// - Parameters:
    ///   - data: The RSS feed data
    ///   - podcastID: The podcast ID to assign to episodes
    /// - Returns: Array of parsed episodes
    /// - Throws: An error if parsing fails
    func parseEpisodesAsync(from data: Data, podcastID: UUID) async throws -> [Episode] {
        // Use the existing parse method and extract episodes from the result
        let (episodes, _) = try await withCheckedThrowingContinuation { continuation in
            // Store the original state
            let originalPodcastID = self.podcastID
            let originalEpisodes = self.episodes
            let originalContinuation = self.continuation
            
            // Set up for this parsing session
            self.podcastID = podcastID
            self.episodes = []
            self.continuation = continuation
            
            // Parse the data
            self.parser = XMLParser(data: data)
            self.parser?.delegate = self
            
            if !self.parser!.parse() {
                let parseError = self.parser!.parserError ?? NSError(domain: "RSSParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown parsing error"])
                continuation.resume(throwing: parseError)
                
                // Restore original state
                self.podcastID = originalPodcastID
                self.episodes = originalEpisodes
                self.continuation = originalContinuation
            }
        }
        
        return episodes
    }
    
    /// Parses an RSS feed from a URL stream asynchronously.
    /// - Parameter url: The URL of the RSS feed.
    /// - Returns: A tuple containing the list of parsed episodes and the podcast's metadata.
    /// - Throws: An error if parsing fails.
    func parse(from url: URL) async throws -> ([Episode], PodcastMetadata) {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            // Use OptimizedNetworkManager for better network handling
            Task {
                do {
                    let data = try await OptimizedNetworkManager.shared.fetchData(url: url)
                    
                    guard !data.isEmpty else {
                        self.logger.error("❌ No data received from RSS feed: \(url)")
                        let error = NSError(domain: "RSSParser", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: "No data received from podcast feed",
                            NSLocalizedRecoverySuggestionErrorKey: "The podcast feed may be temporarily unavailable or the URL may be incorrect."
                        ])
                        self.continuation?.resume(throwing: error)
                        self.continuation = nil
                        return
                    }
                    
                    // Debug: Log the first part of the received data
                    if let dataString = String(data: data, encoding: .utf8) {
                        let preview = String(dataString.prefix(500))
                        self.logger.info("📄 Received data preview: \(preview)")
                        
                        // Check if it looks like XML
                        if dataString.contains("<?xml") || dataString.contains("<rss") || dataString.contains("<feed") {
                            self.logger.info("✅ Data appears to be XML format")
                        } else {
                            self.logger.warning("⚠️ Data does not appear to be XML format")
                        }
                    }
                    
                    // Try to parse as XML first
                    self.parser = XMLParser(data: data)
                    self.parser.delegate = self
                    
                    self.logger.info("🚀 Starting parse for podcast ID: \(self.podcastID) from \(url)")
                    
                    if !self.parser.parse() {
                        let parseError = self.parser.parserError
                        self.logger.error("❌ XML parsing failed. Error: \(parseError?.localizedDescription ?? "Unknown error")")
                        
                        // If XML parsing fails, try to handle as JSON or other format
                        if let dataString = String(data: data, encoding: .utf8) {
                            self.logger.info("📄 Received non-XML response, attempting alternative parsing")
                            self.logger.info("📄 Full response: \(dataString)")
                            
                            // Try to extract any useful information from the response
                            let metadata = PodcastMetadata(
                                title: "Unknown Podcast",
                                author: "Unknown Author", 
                                description: "Podcast data could not be parsed",
                                artworkURL: nil
                            )
                            
                            // Return empty episodes but with metadata
                            self.continuation?.resume(returning: ([], metadata))
                            self.continuation = nil
                        } else {
                            let finalError = parseError ?? NSError(domain: "RSSParser", code: 2, userInfo: [
                                NSLocalizedDescriptionKey: "Failed to parse podcast feed",
                                NSLocalizedRecoverySuggestionErrorKey: "The podcast feed contains invalid data or is in an unsupported format."
                            ])
                            self.logger.error("❌ Parsing failed: \(finalError.localizedDescription)")
                            self.continuation?.resume(throwing: finalError)
                            self.continuation = nil
                        }
                    }
                    
                } catch {
                    self.logger.error("❌ Network error fetching RSS feed: \(error.localizedDescription)")
                    
                    // Provide more specific error messages based on the type of error
                    let enhancedError: NSError
                    if let urlError = error as? URLError {
                        switch urlError.code {
                        case .notConnectedToInternet:
                            enhancedError = NSError(domain: "RSSParser", code: 4, userInfo: [
                                NSLocalizedDescriptionKey: "No internet connection",
                                NSLocalizedRecoverySuggestionErrorKey: "Please check your internet connection and try again."
                            ])
                        case .timedOut:
                            enhancedError = NSError(domain: "RSSParser", code: 5, userInfo: [
                                NSLocalizedDescriptionKey: "Connection timed out",
                                NSLocalizedRecoverySuggestionErrorKey: "The podcast server is not responding. Please try again later."
                            ])
                        case .cannotFindHost, .cannotConnectToHost:
                            enhancedError = NSError(domain: "RSSParser", code: 6, userInfo: [
                                NSLocalizedDescriptionKey: "Cannot connect to podcast server",
                                NSLocalizedRecoverySuggestionErrorKey: "The podcast server may be down or the URL may be incorrect."
                            ])
                        case .badURL:
                            enhancedError = NSError(domain: "RSSParser", code: 7, userInfo: [
                                NSLocalizedDescriptionKey: "Invalid podcast URL",
                                NSLocalizedRecoverySuggestionErrorKey: "The podcast feed URL is malformed or incorrect."
                            ])
                        default:
                            enhancedError = NSError(domain: "RSSParser", code: 8, userInfo: [
                                NSLocalizedDescriptionKey: "Network error: \(error.localizedDescription)",
                                NSLocalizedRecoverySuggestionErrorKey: "Please check your internet connection and try again."
                            ])
                        }
                    } else {
                        enhancedError = NSError(domain: "RSSParser", code: 9, userInfo: [
                            NSLocalizedDescriptionKey: "Failed to fetch podcast feed",
                            NSLocalizedRecoverySuggestionErrorKey: "There was an error downloading the podcast feed. Please try again later."
                        ])
                    }
                    
                    self.continuation?.resume(throwing: enhancedError)
                    self.continuation = nil
                }
            }
        }
    }
    
    // MARK: - Private Progressive Parsing
    
    private func parseDataProgressively(data: Data, completion: @escaping (Result<([Episode], PodcastMetadata), Error>) -> Void) {
        // Set up parser for progressive parsing
        self.parser = XMLParser(data: data)
        self.parser.delegate = self
        
        // Store completion for later use - this is the key fix
        self.progressiveCompletion = completion
        
        // Start parsing in background to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { 
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "RSSParser", code: 99, userInfo: [NSLocalizedDescriptionKey: "Parser was deallocated"])))
                }
                return 
            }
            
            // Set a timeout for parsing to prevent hanging
            let timeoutTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            timeoutTimer.schedule(deadline: .now() + 30.0) // 30 second timeout
            timeoutTimer.setEventHandler { [weak self] in
                self?.parser?.abortParsing()
                DispatchQueue.main.async {
                    let timeoutError = NSError(domain: "RSSParser", code: 10, userInfo: [
                        NSLocalizedDescriptionKey: "Parsing timed out",
                        NSLocalizedRecoverySuggestionErrorKey: "The podcast feed took too long to parse. Please try again."
                    ])
                    self?.progressiveCompletion?(.failure(timeoutError))
                    self?.progressiveCompletion = nil
                }
                timeoutTimer.cancel()
            }
            timeoutTimer.resume()
            
            let parseSuccess = self.parser.parse()
            timeoutTimer.cancel()
            
            if !parseSuccess {
                let parseError = self.parser.parserError ?? NSError(domain: "RSSParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown parsing error"])
                DispatchQueue.main.async {
                    self.progressiveCompletion?(.failure(parseError))
                    self.progressiveCompletion = nil
                }
            }
            // Success case is handled in parserDidEndDocument
        }
    }
    
    // MARK: - XMLParserDelegate Methods
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElementName = elementName
        
        // Debug: Log the first few elements to see if parsing is working
        if self.episodes.isEmpty && (elementName == "rss" || elementName == "feed" || elementName == "channel") {
            logger.info("🔍 XML parsing started - found element: \(elementName)")
        }
        
        switch elementName {
        case "channel":
            isParsingChannel = true
            logger.info("📺 Found channel element")
        case "item":
            isParsingItem = true
            resetCurrentEpisodeData()
            if self.episodes.count < 3 { // Only log first few items
                logger.info("📝 Found item element #\(self.episodes.count + 1)")
            }
        case "enclosure" where isParsingItem:
            if let url = attributeDict["url"], attributeDict["type"]?.hasPrefix("audio") == true {
                currentAudioURL = url
            }
        case "itunes:image", "image":
            handleImageElement(attributes: attributeDict)
        case "media:thumbnail":
             if let url = attributeDict["url"] {
                if isParsingItem {
                    currentEpisodeArtworkURL = url
                } else if isParsingChannel, podcastArtworkURL.isEmpty {
                    podcastArtworkURL = url
                }
            }
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedString.isEmpty else { return }
        
        if isParsingItem {
            // We are inside an <item>
            switch currentElementName {
            case "title":
                currentTitle += string
            case "description", "itunes:summary":
                currentDescription += string
            case "pubDate":
                currentPubDate += string
            default:
                break
            }
        } else if isParsingChannel {
            // We are inside the <channel> but not an <item>
            switch currentElementName {
            case "title":
                if podcastTitle.isEmpty {
                    podcastTitle = trimmedString
                }
            case "itunes:author", "author":
                podcastAuthor += string
            case "description", "itunes:summary":
                podcastDescription += string
            case "url" where podcastArtworkURL.isEmpty:
                 // Handles <image><url>artwork.jpg</url></image>
                podcastArtworkURL = trimmedString
            default:
                break
            }
        }
        
        // Send metadata update if we have enough info and this is progressive parsing
        if progressiveCallback != nil && !podcastTitle.isEmpty && metadataCallback != nil {
            let metadata = PodcastMetadata(
                title: podcastTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                author: podcastAuthor.trimmingCharacters(in: .whitespacesAndNewlines),
                description: podcastDescription.trimmingCharacters(in: .whitespacesAndNewlines).cleanedEpisodeDescription,
                artworkURL: URL(string: podcastArtworkURL)
            )
            
            DispatchQueue.main.async { [weak self] in
                self?.metadataCallback?(metadata)
                self?.metadataCallback = nil // Only send once
            }
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            createEpisode()
            isParsingItem = false
            
            // Progressive UI update - OPTIMIZED: Reduce main thread pressure
            if let progressiveCallback = progressiveCallback {
                episodeCount += 1
                
                // Only update UI every 10 episodes or at the end to reduce main thread pressure
                if episodeCount % 10 == 0 {
                    if let lastEpisode = episodes.last {
                        DispatchQueue.main.async {
                            progressiveCallback(lastEpisode)
                        }
                        
                        if episodeCount <= 30 { // Log first 30 episodes
                            logger.info("📱 Progressive update: Episode #\(self.episodeCount) - \(lastEpisode.title)")
                        }
                    }
                }
            }
        } else if elementName == "channel" {
            isParsingChannel = false
        }
    }
    
    func parserDidEndDocument(_ parser: XMLParser) {
        logger.info("✅ Successfully finished parsing document. Found \(self.episodes.count) episodes.")
        
        // For progressive parsing, send any remaining episodes in a single batch
        if let progressiveCallback = progressiveCallback {
            // Send remaining episodes that weren't sent in batches - OPTIMIZED: Single main thread call
            let remainingStart = (episodeCount / 10) * 10
            if remainingStart < episodes.count {
                DispatchQueue.main.async {
                    // Send all remaining episodes at once
                    for i in remainingStart..<self.episodes.count {
                        progressiveCallback(self.episodes[i])
                    }
                }
            }
        }
        
        let metadata = PodcastMetadata(
            title: podcastTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            author: podcastAuthor.trimmingCharacters(in: .whitespacesAndNewlines),
            description: podcastDescription.trimmingCharacters(in: .whitespacesAndNewlines).cleanedEpisodeDescription,
            artworkURL: URL(string: podcastArtworkURL)
        )
        
        // Handle both continuation and progressive completion patterns
        if let continuation = continuation {
            continuation.resume(returning: (episodes, metadata))
            self.continuation = nil
        }
        
        if let progressiveCompletion = progressiveCompletion {
            DispatchQueue.main.async {
                progressiveCompletion(.success((self.episodes, metadata)))
            }
            self.progressiveCompletion = nil
        }
    }
    
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        logger.error("❌ XML Parser Error: \(parseError.localizedDescription) at Line: \(parser.lineNumber), Column: \(parser.columnNumber)")
        
        // Handle both continuation and progressive completion patterns
        if let continuation = continuation {
            continuation.resume(throwing: parseError)
            self.continuation = nil
        }
        
        if let progressiveCompletion = progressiveCompletion {
            DispatchQueue.main.async {
                progressiveCompletion(.failure(parseError))
            }
            self.progressiveCompletion = nil
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func resetCurrentEpisodeData() {
        currentTitle = ""
        currentAudioURL = ""
        currentDescription = ""
        currentPubDate = ""
        currentEpisodeArtworkURL = ""
    }
    
    private func handleImageElement(attributes: [String: String]) {
        if let url = attributes["href"] ?? attributes["url"] {
            if isParsingItem {
                currentEpisodeArtworkURL = url
            } else if isParsingChannel, podcastArtworkURL.isEmpty {
                podcastArtworkURL = url
            }
        }
    }
    
    private func createEpisode() {
        guard let audioURL = URL(string: currentAudioURL) else {
            logger.warning("⚠️ Skipping item with missing or invalid audio URL. Title: \(self.currentTitle)")
            return
        }
        
        let episode = Episode(
            id: UUID(),
            title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            artworkURL: URL(string: currentEpisodeArtworkURL),
            audioURL: audioURL,
            description: currentDescription.trimmingCharacters(in: .whitespacesAndNewlines).cleanedEpisodeDescription,
            played: false,
            podcastID: self.podcastID,
            publishedDate: RSSParser.dateFrom(pubDate: currentPubDate),
            localFileURL: nil,
            playbackPosition: 0
        )
        episodes.append(episode)
    }
    
    // MARK: - Static Date Parsing Helper
    
    static func dateFrom(pubDate: String) -> Date? {
        let formats = [
            "E, d MMM yyyy HH:mm:ss Z",
            "E, d MMM yyyy HH:mm:ss zzz",
            "E, d MMM yyyy HH:mm:ss z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: pubDate) {
                return date
            }
        }
        return nil
    }
}

/// A structure to hold the parsed metadata of a podcast.
struct PodcastMetadata {
    var title: String?
    var author: String?
    var description: String?
    var artworkURL: URL?
} 