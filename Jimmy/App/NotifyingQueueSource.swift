import Foundation
import JimmyKit

/// Wraps JimmyKit's `StorePlaybackSource` so a `Playback`-driven queue removal (auto-advance
/// dequeuing a finished episode) posts the same `.episodeRemovedFromQueue` notification
/// `AppModel.dequeue` posts for a user-initiated one. Old `ObservableObject` screens that can't use
/// `@Observable` tracking (e.g. `EpisodeDetailViewModel.isInQueue`) rely on this notification to
/// notice an episode leaving the queue, including when `Playback` removes it itself.
struct NotifyingQueueSource: QueueSource {
    private let inner: StorePlaybackSource

    init(store: Store) {
        self.inner = StorePlaybackSource(store: store)
    }

    func episode(after episodeID: UUID?) async -> JimmyKit.Episode? {
        await inner.episode(after: episodeID)
    }

    func removeFinished(_ episodeID: UUID) async {
        await inner.removeFinished(episodeID)
        NotificationCenter.default.post(name: .episodeRemovedFromQueue, object: episodeID)
    }
}
