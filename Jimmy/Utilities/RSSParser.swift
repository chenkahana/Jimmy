import Foundation

class RSSParser: NSObject, XMLParserDelegate {
    private var episodes: [Episode] = []
    private var currentTitle: String = ""
    private var currentAudioURL: String = ""
    private var currentDescription: String = ""
    private var currentPubDate: String = ""
    private var currentEpisodeArtworkURL: String = ""
    private var parsingItem = false
    private var podcastID: UUID?
    private var podcastArtworkURL: String = ""
    private var parsingChannel = false
    private var currentElementName: String = ""
    private var podcastTitle: String = ""
    private var podcastAuthor: String = ""
    private var podcastDescription: String = ""
    
    func parseRSS(data: Data, podcastID: UUID) -> [Episode] {
        self.podcastID = podcastID
        episodes = []
        podcastArtworkURL = ""
        podcastTitle = ""
        podcastAuthor = ""
        podcastDescription = ""
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return episodes
    }
    
    // MARK: - XMLParserDelegate
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElementName = elementName
        
        if elementName == "channel" {
            parsingChannel = true
        }
        if elementName == "item" {
            parsingItem = true
            currentTitle = ""
            currentAudioURL = ""
            currentDescription = ""
            currentPubDate = ""
            currentEpisodeArtworkURL = ""
        }
        if parsingItem && elementName == "enclosure" {
            currentAudioURL = attributeDict["url"] ?? ""
        }
        if parsingChannel && (elementName == "itunes:image" || elementName == "image") {
            if let url = attributeDict["href"] ?? attributeDict["url"] {
                podcastArtworkURL = url
            }
        }
        if parsingItem && (elementName == "itunes:image" || elementName == "image") {
            if let url = attributeDict["href"] ?? attributeDict["url"] {
                currentEpisodeArtworkURL = url
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if parsingChannel && !parsingItem {
            if currentElementName == "title" {
                podcastTitle += string
            } else if currentElementName == "itunes:author" || currentElementName == "author" {
                podcastAuthor += string
            } else if currentElementName == "description" || currentElementName == "itunes:summary" {
                podcastDescription += string
            }
        } else if parsingItem {
            if currentElementName == "title" {
                currentTitle += string
            } else if currentElementName == "description" {
                currentDescription += string
            } else if currentElementName == "pubDate" {
                currentPubDate += string
            }
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "channel" {
            parsingChannel = false
        }
        if elementName == "item" && parsingItem {
            if let audioURL = URL(string: currentAudioURL), let podcastID = podcastID {
                let date = RSSParser.dateFrom(pubDate: currentPubDate)
                let episodeArtwork = !currentEpisodeArtworkURL.isEmpty ? URL(string: currentEpisodeArtworkURL) : nil
                
                // Use raw title with basic trimming, no parsing
                let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanedDescription = currentDescription.trimmingCharacters(in: .whitespacesAndNewlines).cleanedEpisodeDescription
                
                let episode = Episode(
                    id: UUID(),
                    title: title,
                    artworkURL: episodeArtwork,
                    audioURL: audioURL,
                    description: cleanedDescription.isEmpty ? nil : cleanedDescription,
                    played: false,
                    podcastID: podcastID,
                    publishedDate: date,
                    localFileURL: nil,
                    playbackPosition: 0
                )
                episodes.append(episode)
            }
            parsingItem = false
        }
        currentElementName = ""
    }
    
    // Helper to parse pubDate string
    static func dateFrom(pubDate: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "E, d MMM yyyy HH:mm:ss Z"
        return formatter.date(from: pubDate)
    }
    
    // Add a public accessor for the artwork URL
    func getPodcastArtworkURL() -> String? {
        return podcastArtworkURL.isEmpty ? nil : podcastArtworkURL
    }
    
    // Public accessor for podcast title
    func getPodcastTitle() -> String? {
        return podcastTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : podcastTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Public accessor for podcast author
    func getPodcastAuthor() -> String? {
        return podcastAuthor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : podcastAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Public accessor for podcast description
    func getPodcastDescription() -> String? {
        let cleaned = podcastDescription.trimmingCharacters(in: .whitespacesAndNewlines).cleanedEpisodeDescription
        return cleaned.isEmpty ? nil : cleaned
    }
} 