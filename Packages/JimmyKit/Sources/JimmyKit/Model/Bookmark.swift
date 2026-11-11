import Foundation

/// A user-created bookmark at a specific timestamp in an episode.
public nonisolated struct Bookmark: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var episodeID: UUID
    public var timestamp: TimeInterval
    public var note: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        episodeID: UUID,
        timestamp: TimeInterval,
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.episodeID = episodeID
        self.timestamp = timestamp
        self.note = note
        self.createdAt = createdAt
    }
}
