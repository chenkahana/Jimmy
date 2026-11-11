import Foundation

/// An episode's membership and position in the play queue.
public nonisolated struct QueueEntry: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID { episodeID }
    public var episodeID: UUID
    /// 0-based position in the queue; lower plays sooner.
    public var position: Int

    public init(episodeID: UUID, position: Int) {
        self.episodeID = episodeID
        self.position = position
    }
}
