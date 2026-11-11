import Foundation
import JimmyKit

/// What the Suggestions screen needs from the app, kept behind a protocol so tests exercise
/// ranking/UI logic against a fake instead of a real `Store`/network search — the same shape as
/// `Jimmy/Assistant/AssistantActions.swift`. `AppModel` conforms in
/// `Jimmy/App/AppModel+Suggestions.swift`; `libraryPodcasts()`/`libraryEpisodes()`/`playNow(_:)`
/// are already implemented there via `AssistantActions` and satisfy this protocol unchanged.
@MainActor
protocol SuggestionsActions: AnyObject, Sendable {
    /// Podcasts in the user's library, for ranking and for excluding already-subscribed shows
    /// from "new shows like yours".
    func libraryPodcasts() async -> [JimmyKit.Podcast]
    /// Episodes across every subscribed podcast — `SuggestionsRanker`'s candidate pool and its
    /// source of per-show listening history.
    func libraryEpisodes() async -> [JimmyKit.Episode]
    /// Every episode's progress row (see `SuggestionsRanker`).
    func allProgress() async -> [JimmyKit.Progress]
    /// Day-level listening time, optionally attributed to a podcast (see `SuggestionsRanker`).
    func listeningStats() async -> [JimmyKit.ListeningStat]
    /// Episode ids already in the queue, excluded from "up next" (they're already up next).
    func queuedEpisodeIDs() -> Set<UUID>

    /// Loads `episode` and starts playing it.
    func playNow(_ episode: JimmyKit.Episode) async
    /// Adds `episode` to the end of the queue.
    func queueEpisode(_ episode: JimmyKit.Episode) async

    /// Apple Podcasts search (title/author/feed), seeded by `SuggestionsRanker.seedQueries`.
    func searchPodcastsForSuggestions(query: String) async -> [SuggestedShowResult]
    /// Subscribes to `feedURL`.
    func subscribe(feedURL: URL) async throws -> JimmyKit.Podcast
}

/// A trimmed-down Apple Podcasts search hit for "new shows like the ones you finish" — just what
/// the Suggestions screen needs, so it doesn't depend on the legacy `PodcastSearchResult`/
/// `iTunesSearchService` types directly.
struct SuggestedShowResult: Sendable, Equatable, Identifiable {
    var id: URL { feedURL }
    let title: String
    let author: String
    let feedURL: URL
    let artworkURL: URL?
}
