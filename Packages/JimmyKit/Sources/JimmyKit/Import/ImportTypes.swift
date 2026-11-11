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

/// The outcome of parsing an import source: the feeds found, and anything left out.
public nonisolated struct ImportResult: Sendable, Hashable {
    public let feeds: [ImportedFeed]
    public let skipped: [Skipped]

    public init(feeds: [ImportedFeed], skipped: [Skipped]) {
        self.feeds = feeds
        self.skipped = skipped
    }
}

/// Thrown when an import source cannot be parsed at all.
public nonisolated enum ImportError: Error, Sendable, Equatable {
    case malformed
}
