import Foundation

/// An episode of a podcast. Playback progress lives in `Progress`, queue membership in `QueueEntry`,
/// and downloaded-file state in `Download` — this type carries only feed-derived and user-flag data.
public nonisolated struct Episode: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var podcastID: UUID?
    public var title: String
    public var audioURL: URL?
    public var publishedDate: Date?
    public var duration: TimeInterval?
    public var artworkURL: URL?
    public var description: String?
    /// Unseen-by-the-user indicator, independent of playback progress.
    public var isNew: Bool
    /// When this episode was last fetched from the feed.
    public var fetchedAt: Date
    /// 1-based feed page this episode was fetched from.
    public var page: Int
    public var starred: Bool

    public init(
        id: UUID = UUID(),
        podcastID: UUID? = nil,
        title: String,
        audioURL: URL? = nil,
        publishedDate: Date? = nil,
        duration: TimeInterval? = nil,
        artworkURL: URL? = nil,
        description: String? = nil,
        isNew: Bool = true,
        fetchedAt: Date = Date(),
        page: Int = 1,
        starred: Bool = false
    ) {
        self.id = id
        self.podcastID = podcastID
        self.title = title
        self.audioURL = audioURL
        self.publishedDate = publishedDate
        self.duration = duration
        self.artworkURL = artworkURL
        self.description = description
        self.isNew = isNew
        self.fetchedAt = fetchedAt
        self.page = page
        self.starred = starred
    }
}
