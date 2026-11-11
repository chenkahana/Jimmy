import Foundation

/// Playback progress for an episode — the one source of truth replacing today's
/// `episodes.playbackPosition` / `.played` / `.status` and `playback_state.position` / `.finished`.
public nonisolated struct Progress: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID { episodeID }
    public var episodeID: UUID
    public var position: TimeInterval
    public var duration: TimeInterval?
    public var isFinished: Bool
    public var updatedAt: Date

    /// Fraction of `duration` played at which an episode counts as finished.
    public static let finishedThreshold: Double = 0.95

    /// Whether `position`/`duration` cross `finishedThreshold`.
    ///
    /// Today's app disagrees with itself on this comparison: `EpisodeWithStatus.deriveStatus` uses
    /// `>=` while `AudioPlayerService` uses `>`. This picks `>=`.
    public static func isFinished(position: TimeInterval, duration: TimeInterval?) -> Bool {
        guard let duration, duration > 0 else { return false }
        return position / duration >= finishedThreshold
    }

    public init(
        episodeID: UUID,
        position: TimeInterval,
        duration: TimeInterval? = nil,
        isFinished: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.episodeID = episodeID
        self.position = position
        self.duration = duration
        self.isFinished = isFinished
        self.updatedAt = updatedAt
    }
}
