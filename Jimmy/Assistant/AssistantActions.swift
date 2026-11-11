import Foundation
import JimmyKit

/// What the on-device assistant's tools (`AssistantTools.swift`) are allowed to do to the app,
/// kept behind a protocol so tests exercise each tool's argument-parsing and matching logic
/// against a fake instead of a real `Store`, `Playback`, or network search. `AppModel` conforms in
/// `Jimmy/App/AppModel+Assistant.swift`.
///
/// Destructive actions (`unsubscribe`, `clearQueue`) are reachable here, but the tools that call
/// them never call them directly from the model's tool call — see `AssistantConfirmationBroker`.
@MainActor
protocol AssistantActions: AnyObject, Sendable {
    /// Podcasts in the user's library, for show-name search and subscribe/unsubscribe lookups.
    func libraryPodcasts() async -> [JimmyKit.Podcast]
    /// Episodes across every subscribed podcast, for `play`/`queue` matching.
    func libraryEpisodes() async -> [JimmyKit.Episode]

    /// Loads `episode` and starts playing it (`AppModel.play`).
    func playNow(_ episode: JimmyKit.Episode) async
    /// Adds `episode` to the queue — at the end, or next (position 2) if `playNext`.
    func queueEpisode(_ episode: JimmyKit.Episode, playNext: Bool) async
    /// Empties the queue. Only ever called after the user has confirmed.
    func clearQueue() async
    /// The queue's episodes, in play order.
    func currentQueue() -> [JimmyKit.Episode]
    /// What's playing right now, if anything.
    func nowPlayingEpisode() -> JimmyKit.Episode?

    /// Apple Podcasts search (title/author/feed), for the `search` and `subscribe` tools.
    func searchApplePodcasts(query: String) async -> [AssistantPodcastResult]
    /// Subscribes to `feedURL`.
    func subscribe(feedURL: URL) async throws
    /// Unsubscribes from `podcastID`. Only ever called after the user has confirmed.
    func unsubscribe(_ podcastID: UUID) async throws

    /// Starts the sleep timer for `minutes` minutes, or — when `minutes` is `nil` — at the end of
    /// the current episode.
    func setSleepTimer(minutes: Int?)
}

/// A trimmed-down Apple Podcasts search hit: just what the assistant's tools need, so they don't
/// have to depend on the legacy `PodcastSearchResult`/`iTunesSearchService` types directly.
struct AssistantPodcastResult: Sendable, Equatable {
    let title: String
    let author: String
    let feedURL: URL
}

/// Matches a person's spoken query ("the latest Daily", "Radiolab") against the library's
/// episodes, preferring an episode whose own title contains the query, then falling back to the
/// newest episode of a podcast whose name contains it. Pure and synchronous so it's trivially
/// testable without touching `AssistantActions`.
enum AssistantEpisodeMatcher {
    static func bestMatch(
        for query: String,
        episodes: [JimmyKit.Episode],
        podcasts: [JimmyKit.Podcast]
    ) -> JimmyKit.Episode? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }

        if let titleMatch = episodes.first(where: { $0.title.lowercased().contains(needle) }) {
            return titleMatch
        }

        guard let podcast = bestMatchingPodcast(for: needle, podcasts: podcasts) else { return nil }
        return episodes
            .filter { $0.podcastID == podcast.id }
            .sorted { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
            .first
    }

    static func bestMatchingPodcast(for query: String, podcasts: [JimmyKit.Podcast]) -> JimmyKit.Podcast? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        return podcasts.first {
            $0.title.lowercased().contains(needle) || $0.cleanTitle.lowercased().contains(needle)
        }
    }
}
