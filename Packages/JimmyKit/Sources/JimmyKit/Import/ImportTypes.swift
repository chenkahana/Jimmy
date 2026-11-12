import Foundation

/// A single feed discovered while importing a subscription export.
public nonisolated struct ImportedFeed: Sendable, Hashable {
    public let feedURL: URL
    public let title: String?

    public init(feedURL: URL, title: String?) {
        self.feedURL = feedURL
        self.title = title
    }
}

/// An entry from the import source that was not included, and why.
public nonisolated struct Skipped: Sendable, Hashable {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

/// A show known only by name (a Spotify library entry, say), which has to be looked up in the
/// podcast directory before it can be subscribed to.
public nonisolated struct ImportedShowName: Sendable, Hashable {
    public let title: String
    public let publisher: String?

    public init(title: String, publisher: String?) {
        self.title = title
        self.publisher = publisher
    }
}

/// What another app knew about one episode: whether it was played, and how far in.
///
/// Matched to a feed episode by `EpisodeMatcher` after the show is subscribed to — by enclosure
/// URL when the source has one, otherwise by title and date.
public nonisolated struct ImportedEpisodeState: Sendable, Hashable {
    /// The show's feed URL, when the source records which feed the episode came from.
    public var feedURL: URL?
    /// The show's name, when the source has no feed URL (Spotify).
    public var podcastTitle: String?
    public var title: String
    public var enclosureURL: URL?
    public var publishedDate: Date?
    /// Seconds in. `nil` when the source only says played or not.
    public var position: TimeInterval?
    public var isPlayed: Bool
    /// When the listener last touched this episode in the other app.
    public var updatedAt: Date?
    /// Saved for later in the other app (Spotify's Your Episodes), so it belongs in the Queue.
    public var isQueued: Bool

    public init(
        feedURL: URL? = nil,
        podcastTitle: String? = nil,
        title: String,
        enclosureURL: URL? = nil,
        publishedDate: Date? = nil,
        position: TimeInterval? = nil,
        isPlayed: Bool = false,
        updatedAt: Date? = nil,
        isQueued: Bool = false
    ) {
        self.feedURL = feedURL
        self.podcastTitle = podcastTitle
        self.title = title
        self.enclosureURL = enclosureURL
        self.publishedDate = publishedDate
        self.position = position
        self.isPlayed = isPlayed
        self.updatedAt = updatedAt
        self.isQueued = isQueued
    }

    /// Started but not finished.
    public var isInProgress: Bool {
        !isPlayed && (position ?? 0) > 0
    }
}

/// The outcome of parsing an import source: the feeds found, shows that still need a directory
/// lookup, per-episode listening history, and anything left out.
public nonisolated struct ImportResult: Sendable, Hashable {
    public let feeds: [ImportedFeed]
    public let skipped: [Skipped]
    public let showNames: [ImportedShowName]
    public let history: [ImportedEpisodeState]

    public init(
        feeds: [ImportedFeed],
        skipped: [Skipped],
        showNames: [ImportedShowName] = [],
        history: [ImportedEpisodeState] = []
    ) {
        self.feeds = feeds
        self.skipped = skipped
        self.showNames = showNames
        self.history = history
    }

    /// `self` and `other` together, feeds de-duplicated by URL — for several files picked at once.
    public func merged(with other: ImportResult) -> ImportResult {
        let (feeds, duplicateSkips) = FeedDeduplicator.deduplicate(feeds + other.feeds)
        var seenNames = Set<String>()
        let names = (showNames + other.showNames).filter {
            seenNames.insert(TitleNormalizer.key($0.title)).inserted
        }
        return ImportResult(
            feeds: feeds,
            skipped: skipped + other.skipped + duplicateSkips,
            showNames: names,
            history: history + other.history
        )
    }

    public var isEmpty: Bool {
        feeds.isEmpty && showNames.isEmpty && history.isEmpty
    }
}

/// Thrown when an import source cannot be parsed at all.
public nonisolated enum ImportError: Error, Sendable, Equatable {
    case malformed
}
