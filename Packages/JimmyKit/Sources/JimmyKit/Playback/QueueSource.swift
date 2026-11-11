import Foundation

/// Read access to the play queue that `Playback` needs for auto-advance. Backed by the
/// (parallel-authored) Store module in the real app; kept as a protocol so `Playback` doesn't
/// depend on that work directly.
public protocol QueueSource {
    /// The episode that should play after `episodeID` (the currently/just-finished episode),
    /// or `nil` if the queue is empty.
    func episode(after episodeID: UUID?) async -> Episode?

    /// Remove a finished episode from the queue.
    func removeFinished(_ episodeID: UUID) async
}
