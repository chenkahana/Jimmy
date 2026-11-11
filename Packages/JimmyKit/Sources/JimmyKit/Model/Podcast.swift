import Foundation

/// A subscribed podcast feed.
public nonisolated struct Podcast: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var title: String
    /// `title` with duplicate halves/patterns stripped, for display.
    public var cleanTitle: String
    public var author: String
    public var description: String
    public var feedURL: URL
    public var artworkURL: URL?
    public var autoAddToQueue: Bool
    public var notificationsEnabled: Bool
    public var lastEpisodeDate: Date?
    /// HTTP ETag from the last feed fetch, for conditional requests.
    public var etag: String?
    public var lastFetched: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        cleanTitle: String,
        author: String,
        description: String = "",
        feedURL: URL,
        artworkURL: URL? = nil,
        autoAddToQueue: Bool = false,
        notificationsEnabled: Bool = false,
        lastEpisodeDate: Date? = nil,
        etag: String? = nil,
        lastFetched: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.cleanTitle = cleanTitle
        self.author = author
        self.description = description
        self.feedURL = feedURL
        self.artworkURL = artworkURL
        self.autoAddToQueue = autoAddToQueue
        self.notificationsEnabled = notificationsEnabled
        self.lastEpisodeDate = lastEpisodeDate
        self.etag = etag
        self.lastFetched = lastFetched
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
