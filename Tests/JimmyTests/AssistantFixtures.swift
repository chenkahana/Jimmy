import Foundation
@testable import Jimmy
import JimmyKit

/// Records every call so tool/view-model tests can assert exactly what was invoked, with what
/// arguments, without ever touching a real `AppModel`/`Store`/network.
@MainActor
final class FakeAssistantActions: AssistantActions {
    var podcastsToReturn: [JimmyKit.Podcast] = []
    var episodesToReturn: [JimmyKit.Episode] = []
    var searchResultsToReturn: [AssistantPodcastResult] = []
    var queueToReturn: [JimmyKit.Episode] = []
    var nowPlayingToReturn: JimmyKit.Episode?
    var subscribeError: Error?

    private(set) var playedEpisodes: [JimmyKit.Episode] = []
    private(set) var queuedEpisodes: [(episode: JimmyKit.Episode, playNext: Bool)] = []
    private(set) var clearQueueCallCount = 0
    private(set) var subscribedFeedURLs: [URL] = []
    private(set) var unsubscribedPodcastIDs: [UUID] = []
    private(set) var sleepTimerMinutes: [Int?] = []

    func libraryPodcasts() async -> [JimmyKit.Podcast] { podcastsToReturn }
    func libraryEpisodes() async -> [JimmyKit.Episode] { episodesToReturn }

    func playNow(_ episode: JimmyKit.Episode) async {
        playedEpisodes.append(episode)
    }

    func queueEpisode(_ episode: JimmyKit.Episode, playNext: Bool) async {
        queuedEpisodes.append((episode, playNext))
    }

    func clearQueue() async {
        clearQueueCallCount += 1
    }

    func currentQueue() -> [JimmyKit.Episode] { queueToReturn }
    func nowPlayingEpisode() -> JimmyKit.Episode? { nowPlayingToReturn }
    func searchApplePodcasts(query: String) async -> [AssistantPodcastResult] { searchResultsToReturn }

    func subscribe(feedURL: URL) async throws -> JimmyKit.Podcast {
        if let subscribeError { throw subscribeError }
        subscribedFeedURLs.append(feedURL)
        return JimmyKit.Podcast(title: "Subscribed", cleanTitle: "Subscribed", author: "", feedURL: feedURL)
    }

    func unsubscribe(_ podcastID: UUID) async {
        unsubscribedPodcastIDs.append(podcastID)
    }

    func setSleepTimer(minutes: Int?) {
        sleepTimerMinutes.append(minutes)
    }
}

struct FakeAssistantError: Error {}

/// A model session that replays canned chunks instead of calling the real on-device model.
@MainActor
final class FakeAssistantModelSession: AssistantModelSession {
    var chunksToStream: [String] = []
    var errorToThrow: Error?
    private(set) var lastPrompt: String?

    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, Error> {
        lastPrompt = prompt
        let chunks = chunksToStream
        let error = errorToThrow
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }
}

extension JimmyKit.Episode {
    static func fixture(
        title: String,
        podcastID: UUID? = nil,
        publishedDate: Date? = nil
    ) -> JimmyKit.Episode {
        JimmyKit.Episode(podcastID: podcastID, title: title, publishedDate: publishedDate)
    }
}

extension JimmyKit.Podcast {
    static func fixture(title: String, feedURL: URL = URL(string: "https://example.com/feed")!) -> JimmyKit.Podcast {
        JimmyKit.Podcast(title: title, cleanTitle: title, author: "Fixture Author", feedURL: feedURL)
    }
}
