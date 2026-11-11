import Foundation
import GRDB
import JimmyKit

/// Podcast detail, episode rows, and episode detail: the one place these screens read episodes
/// (joined with progress/queue/download state), mark played/unplayed, and read/write bookmarks,
/// transcripts, and chapters — all through `Store` directly.
extension AppModel {
    /// One-shot fetch of `episodeID`'s current `JimmyKit.Episode`, or `nil` if it doesn't exist
    /// (e.g. deleted since a cached navigation target was captured) or the store isn't ready.
    func episode(id episodeID: UUID) async -> JimmyKit.Episode? {
        guard let readyStore else { return nil }
        return try? await readyStore.episode(id: episodeID)
    }

    func progress(for episodeID: UUID) async -> JimmyKit.Progress? {
        guard let readyStore else { return nil }
        return try? await readyStore.progress(for: episodeID)
    }

    /// An async sequence of `podcastID`'s episodes — or, with `podcastID` nil, every episode
    /// across the whole library — each joined with progress, queue membership, and download
    /// state. `nil` while the store isn't ready.
    func observeEpisodes(podcastID: UUID?) -> AsyncValueObservation<[JimmyKit.EpisodeListItem]>? {
        readyStore?.observeEpisodes(podcastID: podcastID)
    }

    /// Marks `episodeID` played/unplayed. Position is left untouched, matching today's "mark
    /// played" toggle. Also mirrors the toggle into the legacy `episodes.status`/`.played`
    /// columns via `LegacyEpisodeStatusMirror`, so `QueueView` and other screens that haven't
    /// moved onto `progress` yet stay in sync.
    func markPlayed(_ episodeID: UUID) async {
        try? await readyStore?.markPlayed(episodeID)
        if let episodeWithState = try? await DIContainer.shared.episodeRepository.fetchEpisode(by: episodeID) {
            LegacyEpisodeStatusMirror.markPlayed(episodeWithState.episode)
        }
    }

    func markUnplayed(_ episodeID: UUID) async {
        try? await readyStore?.markUnplayed(episodeID)
        if let episodeWithState = try? await DIContainer.shared.episodeRepository.fetchEpisode(by: episodeID) {
            LegacyEpisodeStatusMirror.markUnplayed(episodeWithState.episode)
        }
    }

    // MARK: - Bookmarks

    func bookmarks(for episodeID: UUID) async -> [JimmyKit.Bookmark] {
        (try? await readyStore?.bookmarks(for: episodeID)) ?? []
    }

    @discardableResult
    func addBookmark(episodeID: UUID, timestamp: TimeInterval, note: String = "") async -> JimmyKit.Bookmark? {
        try? await readyStore?.addBookmark(episodeID: episodeID, timestamp: timestamp, note: note)
    }

    func deleteBookmark(_ id: UUID) async {
        try? await readyStore?.deleteBookmark(id)
    }

    // MARK: - Transcript

    func transcript(for episodeID: UUID) async -> JimmyKit.Transcript? {
        try? await readyStore?.transcript(for: episodeID)
    }

    func saveTranscript(_ transcript: JimmyKit.Transcript) async {
        try? await readyStore?.saveTranscript(transcript)
    }

    // MARK: - Chapters

    func chapters(for episodeID: UUID) async -> [JimmyKit.Chapter] {
        (try? await readyStore?.chapters(for: episodeID)) ?? []
    }

    func saveChapters(_ chapters: [JimmyKit.Chapter], for episodeID: UUID) async {
        try? await readyStore?.saveChapters(chapters, for: episodeID)
    }
}
