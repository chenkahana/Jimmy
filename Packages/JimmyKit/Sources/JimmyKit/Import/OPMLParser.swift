import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Parses an OPML subscription export into feeds JimmyKit can import.
public nonisolated enum OPMLParser {
    /// - Throws: `ImportError.malformed` if the document is not well-formed XML.
    public static func parse(data: Data) throws -> ImportResult {
        let collector = OPMLOutlineCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector

        guard parser.parse() else {
            throw ImportError.malformed
        }

        let (feeds, duplicateSkips) = FeedDeduplicator.deduplicate(collector.candidates)
        return ImportResult(feeds: feeds, skipped: collector.skipped + duplicateSkips)
    }
}

/// Collects `<outline>` elements that carry a feed URL while the document is parsed.
///
/// `didStartElement` fires for every `<outline>`, nested or not, so a grouping outline
/// (no `xmlUrl`/`url`) is simply not a candidate while its children still are.
nonisolated final class OPMLOutlineCollector: NSObject, XMLParserDelegate {
    private(set) var candidates: [ImportedFeed] = []
    private(set) var skipped: [Skipped] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "outline" else { return }
        // Today's parser only recognized `xmlUrl`; `url` is accepted as well now.
        guard let feedURLString = attributeDict["xmlUrl"] ?? attributeDict["url"] else { return }
        // An outline with a feed URL but no name is still silently dropped, as today.
        guard let title = attributeDict["text"] ?? attributeDict["title"] else { return }

        guard let url = URL(string: feedURLString), url.scheme != nil, url.host != nil else {
            skipped.append(Skipped(reason: "invalid feed URL: \(feedURLString)"))
            return
        }

        candidates.append(ImportedFeed(feedURL: url, title: title))
    }
}
