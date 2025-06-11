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
    
    private let logger = Logger(subsystem: "com.jimmy.app", category: "RSSParser")
    
    // MARK: - Initialization
    
    init(podcastID: UUID) {
        self.podcastID = podcastID
        super.init()
    }
    
    // MARK: - Public Interface
    
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
            
            let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.logger.error("❌ Network error fetching RSS feed: \(error.localizedDescription)")
                    self.continuation?.resume(throwing: error)
                    self.continuation = nil
                    return
                }
                
                guard let data = data else {
                    self.logger.error("❌ No data received from RSS feed.")
                    self.continuation?.resume(throwing: NSError(domain: "RSSParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                    self.continuation = nil
                    return
                }
                
                self.parser = XMLParser(data: data)
                self.parser.delegate = self
                
                self.logger.info("🚀 Starting memory-efficient RSS parse for podcast ID: \(self.podcastID)")
                
                if !self.parser.parse() {
                    let parseError = self.parser.parserError ?? NSError(domain: "RSSParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown parsing error"])
                    self.logger.error("❌ RSS parsing failed: \(parseError.localizedDescription)")
                    self.continuation?.resume(throwing: parseError)
                    self.continuation = nil
                }
            }
            task.resume()
        }
    }
    
    // MARK: - XMLParserDelegate Methods
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElementName = elementName
        
        switch elementName {
        case "channel":
            isParsingChannel = true
        case "item":
            isParsingItem = true
            resetCurrentEpisodeData()
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
                podcastTitle += string
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
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            createEpisode()
            isParsingItem = false
        } else if elementName == "channel" {
            isParsingChannel = false
        }
    }
    
    func parserDidEndDocument(_ parser: XMLParser) {
        logger.info("✅ Successfully finished parsing document. Found \(self.episodes.count) episodes.")
        let metadata = PodcastMetadata(
            title: podcastTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            author: podcastAuthor.trimmingCharacters(in: .whitespacesAndNewlines),
            description: podcastDescription.trimmingCharacters(in: .whitespacesAndNewlines).cleanedEpisodeDescription,
            artworkURL: URL(string: podcastArtworkURL)
        )
        continuation?.resume(returning: (episodes, metadata))
        continuation = nil
    }
    
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        logger.error("❌ XML Parser Error: \(parseError.localizedDescription) at Line: \(parser.lineNumber), Column: \(parser.columnNumber)")
        continuation?.resume(throwing: parseError)
        continuation = nil
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