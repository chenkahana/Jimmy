import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Parses an OPML subscription export into feeds JimmyKit can import.
///
/// Also reads Overcast's "extended" OPML: each feed outline there nests one
/// `<outline type="podcast-episode">` per episode the listener touched, carrying `played`,
/// `progress` (seconds), `enclosureUrl`, `pubDate` and `userUpdatedDate`. Those become
/// `ImportResult.history`. A feed marked `subscribed="0"` (one the listener left) is skipped,
/// along with its episodes.
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
        return ImportResult(feeds: feeds, skipped: collector.skipped + duplicateSkips, history: collector.history)
    }
}

/// Collects `<outline>` elements that carry a feed URL while the document is parsed.
///
/// `didStartElement` fires for every `<outline>`, nested or not, so a grouping outline
/// (no `xmlUrl`/`url`) is simply not a candidate while its children still are.
nonisolated final class OPMLOutlineCollector: NSObject, XMLParserDelegate {
    private(set) var candidates: [ImportedFeed] = []
    private(set) var skipped: [Skipped] = []
    private(set) var history: [ImportedEpisodeState] = []

    /// One entry per open `<outline>`: the feed it declares, if any. An episode outline belongs
    /// to the nearest enclosing feed.
    private var feedStack: [FeedContext?] = []

    private struct FeedContext {
        let feedURL: URL
        let isSubscribed: Bool
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "outline" else { return }

        if attributeDict["type"] == "podcast-episode" {
            feedStack.append(nil)
            collectEpisode(attributeDict)
            return
        }

        feedStack.append(collectFeed(attributeDict))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "outline", !feedStack.isEmpty else { return }
        feedStack.removeLast()
    }

    private func collectFeed(_ attributes: [String: String]) -> FeedContext? {
        // Today's parser only recognized `xmlUrl`; `url` is accepted as well now.
        guard let feedURLString = attributes["xmlUrl"] ?? attributes["url"] else { return nil }
        // An outline with a feed URL but no name is still silently dropped, as today.
        guard let title = attributes["text"] ?? attributes["title"] else { return nil }

        guard let url = URL(string: feedURLString), url.scheme != nil, url.host != nil else {
            skipped.append(Skipped(reason: "invalid feed URL: \(feedURLString)"))
            return nil
        }

        let isSubscribed = attributes["subscribed"] != "0"
        if isSubscribed {
            candidates.append(ImportedFeed(feedURL: url, title: title))
        } else {
            skipped.append(Skipped(reason: "not subscribed: \(title)"))
        }
        return FeedContext(feedURL: FeedURLNormalizer.fetchableURL(for: url), isSubscribed: isSubscribed)
    }

    private func collectEpisode(_ attributes: [String: String]) {
        guard let feed = feedStack.dropLast().last(where: { $0 != nil }) ?? nil, feed.isSubscribed else { return }
        guard let title = attributes["title"] ?? attributes["text"], !title.isEmpty else { return }

        let position = attributes["progress"].flatMap(TimeInterval.init)
        let isPlayed = attributes["played"] == "1"
        // Neither played nor started: Overcast lists it, but there's nothing to bring over.
        guard isPlayed || (position ?? 0) > 0 else { return }

        history.append(ImportedEpisodeState(
            feedURL: feed.feedURL,
            title: title,
            enclosureURL: attributes["enclosureUrl"].flatMap(URL.init(string:)),
            publishedDate: attributes["pubDate"].flatMap(ImportDates.parse),
            position: position,
            isPlayed: isPlayed,
            updatedAt: attributes["userUpdatedDate"].flatMap(ImportDates.parse)
        ))
    }
}

/// Dates as podcast apps write them in their exports.
nonisolated enum ImportDates {
    static func parse(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if let date = try? Date(trimmed, strategy: .iso8601) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm:ssZZZZZ", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }
}
