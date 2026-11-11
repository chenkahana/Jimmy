import Foundation
@testable import Jimmy
import JimmyKit

/// Records every call so Suggestions view-model tests can assert exactly what was fetched or
/// invoked, without ever touching a real `AppModel`/`Store`/network — the same pattern as
/// `FakeAssistantActions`.
@MainActor
final class FakeSuggestionsActions: SuggestionsActions {
    var podcastsToReturn: [JimmyKit.Podcast] = []
    var episodesToReturn: [JimmyKit.Episode] = []
    var progressToReturn: [JimmyKit.Progress] = []
    var listeningStatsToReturn: [JimmyKit.ListeningStat] = []
    var queuedIDsToReturn: Set<UUID> = []
    var searchResultsByQuery: [String: [SuggestedShowResult]] = [:]
    var subscribeError: Error?

    private(set) var playedEpisodes: [JimmyKit.Episode] = []
    private(set) var queuedEpisodes: [JimmyKit.Episode] = []
    private(set) var searchedQueries: [String] = []
    private(set) var subscribedFeedURLs: [URL] = []

    func libraryPodcasts() async -> [JimmyKit.Podcast] { podcastsToReturn }
    func libraryEpisodes() async -> [JimmyKit.Episode] { episodesToReturn }
    func allProgress() async -> [JimmyKit.Progress] { progressToReturn }
    func listeningStats() async -> [JimmyKit.ListeningStat] { listeningStatsToReturn }
    func queuedEpisodeIDs() -> Set<UUID> { queuedIDsToReturn }

    func playNow(_ episode: JimmyKit.Episode) async {
        playedEpisodes.append(episode)
    }

    func queueEpisode(_ episode: JimmyKit.Episode) async {
        queuedEpisodes.append(episode)
    }

    func searchPodcastsForSuggestions(query: String) async -> [SuggestedShowResult] {
        searchedQueries.append(query)
        return searchResultsByQuery[query] ?? []
    }

    func subscribe(feedURL: URL) async throws -> JimmyKit.Podcast {
        if let subscribeError { throw subscribeError }
        subscribedFeedURLs.append(feedURL)
        return JimmyKit.Podcast(title: "Subscribed", cleanTitle: "Subscribed", author: "", feedURL: feedURL)
    }
}

/// A model session that returns one canned reason per call instead of calling the real on-device
/// model, recording every prompt it was asked.
@MainActor
final class FakeSuggestionsModelSession: SuggestionsModelSession {
    var reasonToReturn = "Model reason"
    var errorToThrow: Error?
    private(set) var prompts: [String] = []

    func reason(for prompt: String) async throws -> String {
        prompts.append(prompt)
        if let errorToThrow { throw errorToThrow }
        return reasonToReturn
    }
}

struct FakeSuggestionsError: Error {}
