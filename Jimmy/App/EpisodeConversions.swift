import Foundation
import JimmyKit

/// The one boundary between `JimmyKit.Episode` (what `Playback`/`AppModel.queue` deal in) and the
/// app's own, richer `Jimmy.Episode` (what screens not yet moved onto `JimmyKit` — library,
/// podcast detail, episode rows; PR 18 — still render). Every call site that needs to cross
/// between the two converts through here rather than re-implementing the mapping.
extension JimmyKit.Episode {
    /// Converts to the old `Jimmy.Episode` model. Fields `JimmyKit.Episode` doesn't carry
    /// (`played`, `playbackPosition`, `status`, `localFileURL`) are left at their defaults —
    /// callers that need live progress read it from `Playback` directly instead.
    func asLegacyEpisode() -> Jimmy.Episode {
        Jimmy.Episode(
            id: id,
            title: title,
            podcastID: podcastID,
            publishedDate: publishedDate,
            duration: duration,
            artworkURL: artworkURL,
            description: description,
            audioURL: audioURL,
            isNew: isNew,
            lastFetched: fetchedAt,
            starred: starred
        )
    }
}

extension JimmyKit.EpisodeListItem {
    /// Converts to the old `Jimmy.Episode` model, with progress, played state, and queue
    /// membership baked in from `progress`/`isQueued` — unlike `JimmyKit.Episode.asLegacyEpisode()`,
    /// which leaves those fields at their defaults since a bare `JimmyKit.Episode` doesn't carry
    /// them. Used to feed `EpisodeWithStatus`/`EpisodeCard`, which still render the old model.
    func asLegacyEpisode() -> Jimmy.Episode {
        var legacy = episode.asLegacyEpisode()
        legacy.playbackPosition = progress?.position ?? 0
        legacy.played = progress?.isFinished ?? false
        var status: EpisodeStatus = []
        if progress?.isFinished == true { status.insert(.played) }
        if isQueued { status.insert(.queued) }
        legacy.status = status
        return legacy
    }
}

extension JimmyKit.EpisodeListItem {
    /// Converts to the old `EpisodeWithPlaybackState`, for screens that still render that model
    /// (e.g. `EpisodeDetailView`, `SmartPlaylistDetailView`).
    func asLegacyEpisodeWithPlaybackState() -> Jimmy.EpisodeWithPlaybackState {
        Jimmy.EpisodeWithPlaybackState(
            episode: asLegacyEpisode(),
            playbackState: PlaybackState(
                episodeID: episode.id,
                position: progress?.position ?? 0,
                finished: progress?.isFinished ?? false,
                updatedAt: Date()
            )
        )
    }
}

extension Jimmy.Episode {
    /// Converts to the `JimmyKit.Episode` that `Playback.load` needs to play this episode.
    func asPlaybackEpisode() -> JimmyKit.Episode {
        JimmyKit.Episode(
            id: id,
            podcastID: podcastID,
            title: title,
            audioURL: audioURL,
            publishedDate: publishedDate,
            duration: duration,
            artworkURL: artworkURL,
            description: description,
            isNew: isNew,
            fetchedAt: lastFetched ?? Date(),
            page: 1,
            starred: starred
        )
    }
}

extension JimmyKit.Podcast {
    /// Converts to the old `Jimmy.Podcast` model (same table, same columns — see
    /// `Packages/JimmyKit/Sources/JimmyKit/Store/Records.swift`), for screens not yet moved onto
    /// `JimmyKit` (podcast detail, episode rows; PR 18) that still render it.
    func asLegacyPodcast() -> Jimmy.Podcast {
        Jimmy.Podcast(
            id: id,
            title: title,
            author: author,
            description: description,
            feedURL: feedURL,
            artworkURL: artworkURL,
            autoAddToQueue: autoAddToQueue,
            notificationsEnabled: notificationsEnabled,
            lastEpisodeDate: lastEpisodeDate,
            etag: etag,
            lastFetched: lastFetched
        )
    }
}
