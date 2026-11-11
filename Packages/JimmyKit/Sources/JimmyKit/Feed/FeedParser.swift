import Foundation

/// The result of parsing one RSS 2.0 or Atom feed document.
nonisolated public struct ParsedFeed: Sendable {
    /// Podcast-level (channel/feed) metadata.
    nonisolated public struct PodcastInfo: Sendable, Equatable {
        public var title: String?
        public var author: String?
        public var description: String?
        public var artworkURL: URL?
        /// `itunes:new-feed-url` — set when the publisher has migrated the feed elsewhere.
        public var newFeedURL: URL?

        public init(
            title: String? = nil,
            author: String? = nil,
            description: String? = nil,
            artworkURL: URL? = nil,
            newFeedURL: URL? = nil
        ) {
            self.title = title
            self.author = author
            self.description = description
            self.artworkURL = artworkURL
            self.newFeedURL = newFeedURL
        }
    }

    public var podcast: PodcastInfo
    public var episodes: [Episode]
    /// `podcast:transcript` for episodes that declared one, keyed by that episode's id.
    public var transcripts: [UUID: Transcript]
    /// `podcast:chapters` URL (a chapters-JSON file, fetched and parsed separately) for
    /// episodes that declared one, keyed by that episode's id.
    public var chaptersURLs: [UUID: URL]

    public init(
        podcast: PodcastInfo,
        episodes: [Episode],
        transcripts: [UUID: Transcript] = [:],
        chaptersURLs: [UUID: URL] = [:]
    ) {
        self.podcast = podcast
        self.episodes = episodes
        self.transcripts = transcripts
        self.chaptersURLs = chaptersURLs
    }
}

/// Errors thrown by ``FeedParser``.
nonisolated public enum FeedError: Error, Sendable, Equatable {
    /// The XML could not be parsed to completion. `reason` is the underlying
    /// `XMLParser` error description, kept for diagnostics/logging.
    case malformed(reason: String)
}

/// Streaming RSS 2.0 / Atom parser.
///
/// This replaces `ConcreteRSSParser`, `AdvancedRSSParser`, `MemoryEfficientStreamingParser`
/// and `EpisodeParser` with a single implementation. It is built on Foundation's
/// `XMLParser` (SAX-style — not fully loaded into a DOM), so it stays memory-efficient
/// on very large feeds.
///
/// ## Policy decisions (see Feed/ README / PR description for detail)
/// - **Malformed XML**: today's real refresh path (`FetchWorker` → `ConcreteRSSParser`)
///   resolves its parsing continuation only from `parserDidEndDocument`; any
///   `parseErrorOccurred` call throws and the caller (`FetchWorker`) discards everything
///   parsed so far for that feed. This parser matches that: on a parse error we throw
///   ``FeedError/malformed(reason:)`` and return no episodes at all — not a partial list.
/// - **Items without a playable enclosure**: kept, with `audioURL == nil`, rather than
///   dropped. `ConcreteRSSParser` technically falls back to the item's `<link>` as an
///   `audioURL` when there's no enclosure, which usually makes the item survive anyway —
///   but that `<link>` is the episode's web page, not audio, so treating it as playable
///   audio is a pre-existing bug, not a case worth preserving. We don't replicate it.
/// - **`content:encoded`**: when present, used as the episode description in place of
///   plain `<description>` (richer HTML body — a common RSS convention); falls back to
///   `<description>` when there's no `content:encoded`.
nonisolated public enum FeedParser: Sendable {
    /// Parses `data` as an RSS 2.0 or Atom feed.
    ///
    /// - Parameters:
    ///   - data: The raw feed document.
    ///   - podcastID: The id to stamp onto every parsed `Episode.podcastID`.
    ///   - feedURL: The feed's own URL — used as an input to episode/podcast ID
    ///     generation and nowhere else.
    /// - Throws: ``FeedError/malformed(reason:)`` if the XML cannot be parsed.
    public static nonisolated func parse(data: Data, podcastID: UUID, feedURL: URL) throws -> ParsedFeed {
        let handler = FeedXMLHandler(podcastID: podcastID, feedURL: feedURL)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = handler

        guard xmlParser.parse() else {
            let reason = xmlParser.parserError?.localizedDescription ?? "Unknown XML parsing error"
            throw FeedError.malformed(reason: reason)
        }

        return handler.makeResult()
    }
}

// MARK: - XML handling

/// Stateful `XMLParserDelegate`. Not isolated to any actor: `XMLParser.parse()` runs
/// synchronously on whatever thread/task calls it and drives this delegate directly —
/// there is never a hop, so there is nothing for actor isolation to protect here.
private nonisolated final class FeedXMLHandler: NSObject, XMLParserDelegate {
    private let podcastID: UUID
    private let feedURL: URL

    private var elementStack: [String] = []
    private var textBuffer = ""

    private var isInItem = false
    private var itemDepth = 0
    private var isInAuthor = false
    /// Stack depth of the <channel> (RSS) or <feed> (Atom) element itself; podcast-level
    /// fields and <item>/<entry> are both direct children, i.e. at `channelDepth + 1`.
    private var channelDepth: Int?

    // Per-episode state, reset at the start of every <item>/<entry>.
    private var title = ""
    private var descriptionText = ""
    private var contentEncodedText = ""
    private var pubDateText = ""
    private var durationText = ""
    private var audioURLString: String?
    private var artworkURLString: String?
    private var transcriptURLString: String?
    private var transcriptTypeString: String?
    private var chaptersURLString: String?

    // Channel/feed-level state.
    private var podcastTitle = ""
    private var podcastAuthor = ""
    private var podcastDescription = ""
    private var podcastArtworkURLString: String?
    private var newFeedURLString: String?

    private var episodes: [Episode] = []
    private var transcripts: [UUID: Transcript] = [:]
    private var chaptersURLs: [UUID: URL] = [:]

    init(podcastID: UUID, feedURL: URL) {
        self.podcastID = podcastID
        self.feedURL = feedURL
    }

    func makeResult() -> ParsedFeed {
        ParsedFeed(
            podcast: ParsedFeed.PodcastInfo(
                title: podcastTitle.isEmpty ? nil : podcastTitle,
                author: podcastAuthor.isEmpty ? nil : podcastAuthor,
                description: podcastDescription.isEmpty ? nil : podcastDescription,
                artworkURL: podcastArtworkURLString.flatMap { URL(string: $0) },
                newFeedURL: newFeedURLString.flatMap { URL(string: $0) }
            ),
            episodes: episodes,
            transcripts: transcripts,
            chaptersURLs: chaptersURLs
        )
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        elementStack.append(elementName)
        textBuffer = ""

        switch elementName {
        case "channel", "feed":
            if channelDepth == nil {
                channelDepth = elementStack.count
            }

        case "item", "entry":
            isInItem = true
            itemDepth = elementStack.count
            resetEpisodeState()

        case "enclosure":
            guard isInItem, elementStack.count == itemDepth + 1 else { break }
            if let url = attributeDict["url"], !url.isEmpty {
                audioURLString = url
            }

        case "link":
            // Atom represents the audio enclosure as <link rel="enclosure" href="...">.
            guard isInItem, elementStack.count == itemDepth + 1 else { break }
            if attributeDict["rel"] == "enclosure", let href = attributeDict["href"], !href.isEmpty {
                audioURLString = href
            }

        case "itunes:image":
            if let href = attributeDict["href"] {
                if isInItem, elementStack.count == itemDepth + 1 {
                    artworkURLString = href
                } else if !isInItem {
                    podcastArtworkURLString = href
                }
            }

        case "podcast:transcript":
            guard isInItem, elementStack.count == itemDepth + 1 else { break }
            // Take the first transcript only, matching ConcreteRSSParser.
            if transcriptURLString == nil, let url = attributeDict["url"] {
                transcriptURLString = url
                transcriptTypeString = attributeDict["type"]
            }

        case "podcast:chapters":
            guard isInItem, elementStack.count == itemDepth + 1 else { break }
            if let url = attributeDict["url"] {
                chaptersURLString = url
            }

        case "author":
            if !isInItem {
                isInAuthor = true
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            textBuffer += string
        } else if let string = String(data: CDATABlock, encoding: .utf16) {
            textBuffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        defer {
            if !elementStack.isEmpty { elementStack.removeLast() }
        }

        // Only attribute to the field directly enclosing text, not nested elements that
        // happen to share a name (relevant when recovering text inside a malformed item).
        let isDirectItemChild = isInItem && elementStack.count == itemDepth + 1
        let isDirectChannelChild = !isInItem && channelDepth.map { elementStack.count == $0 + 1 } ?? false

        let text = textBuffer
        textBuffer = ""

        if elementName == "item" || elementName == "entry" {
            finishEpisode()
            isInItem = false
            return
        }

        if isInItem {
            guard isDirectItemChild else { return }
            switch elementName {
            case "title":
                title = text
            case "description", "summary":
                descriptionText = text
            case "content:encoded", "content":
                contentEncodedText = text
            case "pubDate", "updated", "published":
                pubDateText = text
            case "itunes:duration":
                durationText = text
            default:
                break
            }
        } else {
            if elementName == "author" {
                isInAuthor = false
                return
            }
            if isInAuthor {
                if elementName == "name", podcastAuthor.isEmpty {
                    podcastAuthor = text
                }
                return
            }
            guard isDirectChannelChild else { return }
            switch elementName {
            case "title":
                podcastTitle = text
            case "itunes:author":
                podcastAuthor = text
            case "description", "subtitle":
                podcastDescription = text
            case "itunes:new-feed-url":
                newFeedURLString = text
            default:
                break
            }
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // XMLParser calls this once and stops; FeedParser.parse(_:) surfaces it via the
        // `xmlParser.parse()` return value / `parserError`, so there is nothing to do here
        // beyond letting the error propagate. We deliberately do not stash any
        // episodes parsed so far — see the malformed-XML policy note on FeedParser.
    }

    // MARK: - Episode construction

    private func resetEpisodeState() {
        title = ""
        descriptionText = ""
        contentEncodedText = ""
        pubDateText = ""
        durationText = ""
        audioURLString = nil
        artworkURLString = nil
        transcriptURLString = nil
        transcriptTypeString = nil
        chaptersURLString = nil
    }

    private func finishEpisode() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let audioURL = audioURLString
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : URL(string: $0) }

        let publishedDate = FeedDateParser.date(from: pubDateText)

        let episodeID = FeedIDs.generateEpisodeID(
            feedURL: feedURL,
            audioURL: audioURL,
            title: trimmedTitle,
            publishedDate: publishedDate
        )

        let description = contentEncodedText.isEmpty ? descriptionText : contentEncodedText

        let episode = Episode(
            id: episodeID,
            podcastID: podcastID,
            title: trimmedTitle,
            audioURL: audioURL,
            publishedDate: publishedDate,
            duration: FeedDurationParser.duration(from: durationText),
            artworkURL: artworkURLString.flatMap { URL(string: $0) },
            description: description.isEmpty ? nil : description
        )
        episodes.append(episode)

        if let transcriptURLString, let transcriptURL = URL(string: transcriptURLString) {
            let format = FeedTranscriptFormat.format(forMIMEType: transcriptTypeString, url: transcriptURL)
            transcripts[episodeID] = Transcript(episodeID: episodeID, url: transcriptURL, format: format)
        }

        if let chaptersURLString, let chaptersURL = URL(string: chaptersURLString) {
            chaptersURLs[episodeID] = chaptersURL
        }
    }
}

// MARK: - Duration parsing

nonisolated enum FeedDurationParser {
    /// Parses `itunes:duration` in seconds, `MM:SS`, or `HH:MM:SS` form.
    static func duration(from string: String) -> TimeInterval? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let components = trimmed.split(separator: ":").map(String.init)
        switch components.count {
        case 3:
            guard let hours = Double(components[0]),
                  let minutes = Double(components[1]),
                  let seconds = Double(components[2]) else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        case 2:
            guard let minutes = Double(components[0]),
                  let seconds = Double(components[1]) else { return nil }
            return minutes * 60 + seconds
        case 1:
            return Double(components[0])
        default:
            return nil
        }
    }
}

// MARK: - Date parsing

nonisolated enum FeedDateParser {
    /// RFC 822 formats (numeric and named timezones), plus the non-RFC formats the
    /// legacy parsers (`ConcreteRSSParser` / `EpisodeService` / `AdvancedRSSParser`)
    /// accept, plus ISO 8601 (RSS `content:encoded`-adjacent feeds and Atom `<updated>`).
    private static let formats = [
        "E, d MMM yyyy HH:mm:ss Z",
        "E, d MMM yyyy HH:mm:ss zzz",
        "E, d MMM yyyy HH:mm:ss z",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "E, d MMM yyyy HH:mm",
        "MMMM d, yyyy",
        "yyyy-MM-dd",
    ]

    static func date(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Formats without an explicit zone designator (date-only, long-form, short-form)
        // are interpreted as UTC so parsing is deterministic regardless of the host's
        // local timezone; formats that do carry a zone/offset still honor it.
        formatter.timeZone = TimeZone(identifier: "UTC")

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }
}

// MARK: - Transcript format

nonisolated enum FeedTranscriptFormat {
    static func format(forMIMEType mimeType: String?, url: URL) -> TranscriptFormat {
        switch mimeType?.lowercased() {
        case "text/vtt":
            return .vtt
        case "application/x-subrip", "text/srt":
            return .srt
        case "application/json":
            return .json
        default:
            break
        }
        switch url.pathExtension.lowercased() {
        case "vtt": return .vtt
        case "srt": return .srt
        default: return .json
        }
    }
}
