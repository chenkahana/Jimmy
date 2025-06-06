import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

class OPMLParser: NSObject, XMLParserDelegate {
    private var podcasts: [Podcast] = []
    private var currentTitle: String = ""
    private var currentFeedURL: String = ""
    private var currentAuthor: String = ""
    private var currentArtworkURL: String = ""
    
    func parseOPML(from url: URL) -> [Podcast] {
        podcasts = []
        if let parser = XMLParser(contentsOf: url) {
            parser.delegate = self
            parser.parse()
        }
        return podcasts
    }
    
    // MARK: - XMLParserDelegate
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "outline", let feedURL = attributeDict["xmlUrl"], let title = attributeDict["text"] ?? attributeDict["title"] {
            let author = attributeDict["author"] ?? ""
            if let url = URL(string: feedURL) {
                let podcast = Podcast(title: title, author: author, description: "", feedURL: url, artworkURL: nil)
                podcasts.append(podcast)
            }
        }
    }
} 