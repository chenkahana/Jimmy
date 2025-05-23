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
    
    func parseRSS(data: Data, podcastID: UUID) -> [Episode] {
        self.podcastID = podcastID
        episodes = []
        podcastArtworkURL = ""
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
        if parsingItem {
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
                let episode = Episode(
                    id: UUID(),
                    title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    artworkURL: episodeArtwork,
                    audioURL: audioURL,
                    description: currentDescription.trimmingCharacters(in: .whitespacesAndNewlines),
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
} 