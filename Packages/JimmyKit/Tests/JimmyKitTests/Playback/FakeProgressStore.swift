import Foundation
@testable import JimmyKit

final class FakeProgressStore: ProgressStore {
    var stored: [UUID: JimmyKit.Progress] = [:]
    private(set) var savedProgresses: [JimmyKit.Progress] = []

    func loadProgress(for episodeID: UUID) async -> JimmyKit.Progress? {
        stored[episodeID]
    }

    func saveProgress(_ progress: JimmyKit.Progress) async {
        savedProgresses.append(progress)
        stored[progress.episodeID] = progress
    }
}
