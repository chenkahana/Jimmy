import Foundation
@testable import JimmyKit

final class FakeQueueSource: QueueSource {
    /// Episodes up next, in order. `episode(after:)` always returns `queue.first`.
    var queue: [Episode] = []
    private(set) var removedIDs: [UUID] = []

    func episode(after episodeID: UUID?) async -> Episode? {
        queue.first
    }

    func removeFinished(_ episodeID: UUID) async {
        removedIDs.append(episodeID)
        queue.removeAll { $0.id == episodeID }
    }
}
