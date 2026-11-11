import Foundation

/// Adapts `Store` to the non-throwing `ProgressStore`/`QueueSource` protocols `Playback` needs.
///
/// `Store`'s own `progress`/`saveProgress`/`queue` methods throw, surfacing failures to callers
/// that can act on them; `Playback`'s collaborators can't, by design, so this wrapper — not an
/// extension on `Store` itself — drops a failure rather than surfacing it. (`Store` can't conform
/// to `ProgressStore` directly: Swift treats `saveProgress(_:) async` and the existing
/// `saveProgress(_:) async throws` as the same declaration and refuses to compile both.)
public nonisolated struct StorePlaybackSource: ProgressStore, QueueSource, Sendable {
    private let store: Store

    public init(store: Store) {
        self.store = store
    }

    public func loadProgress(for episodeID: UUID) async -> Progress? {
        try? await store.progress(for: episodeID)
    }

    public func saveProgress(_ progress: Progress) async {
        try? await store.saveProgress(progress)
    }

    /// The episode after `episodeID` in queue order, or the first queued episode if `episodeID`
    /// is `nil` or not (or no longer) in the queue.
    public func episode(after episodeID: UUID?) async -> Episode? {
        guard let episodes = try? await store.queue() else { return nil }
        guard let episodeID, let index = episodes.firstIndex(where: { $0.id == episodeID }) else {
            return episodes.first
        }
        let nextIndex = episodes.index(after: index)
        return nextIndex < episodes.count ? episodes[nextIndex] : nil
    }

    public func removeFinished(_ episodeID: UUID) async {
        try? await store.dequeue(episodeID)
    }
}
