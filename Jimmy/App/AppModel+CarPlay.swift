import Foundation
import JimmyKit

/// What `CarPlayManager` (`Jimmy/CarPlay/CarPlayManager.swift`) needs beyond what `AppModel`
/// already keeps live (`queue`, `podcasts`, `playback`): the pure mapping from that data to each
/// template's row titles/subtitles, and the one store read CarPlay needs that nothing else does
/// — a podcast's episode list.
extension AppModel {
    /// One row CarPlay's Queue tab, or a pushed podcast's episode list, shows.
    struct CarPlayEpisodeRow: Equatable {
        let episode: JimmyKit.Episode
        let title: String
        let subtitle: String
    }

    /// One row CarPlay's Library tab shows.
    struct CarPlayPodcastRow: Equatable {
        let podcast: JimmyKit.Podcast
        let title: String
        let subtitle: String
    }

    /// The queue, as CarPlay's Queue tab shows it: title is the episode's own, subtitle its
    /// podcast's title (blank if the podcast isn't in `podcasts`, e.g. just unsubscribed).
    static func carPlayQueueRows(queue: [JimmyKit.Episode], podcasts: [JimmyKit.Podcast]) -> [CarPlayEpisodeRow] {
        queue.map { episode in
            CarPlayEpisodeRow(
                episode: episode,
                title: episode.title,
                subtitle: podcasts.first { $0.id == episode.podcastID }?.title ?? ""
            )
        }
    }

    /// The subscribed podcasts, as CarPlay's Library tab shows them: title is the podcast's own,
    /// subtitle its author.
    static func carPlayLibraryRows(podcasts: [JimmyKit.Podcast]) -> [CarPlayPodcastRow] {
        podcasts.map { CarPlayPodcastRow(podcast: $0, title: $0.title, subtitle: $0.author) }
    }

    /// `episodes`, as CarPlay's podcast-episode list template shows them: title is the episode's
    /// own, subtitle its formatted duration.
    static func carPlayEpisodeRows(_ episodes: [JimmyKit.Episode]) -> [CarPlayEpisodeRow] {
        episodes.map { episode in
            CarPlayEpisodeRow(episode: episode, title: episode.title, subtitle: carPlayDuration(episode.duration))
        }
    }

    /// e.g. "1 hr 5 min", "12 min" — blank for an episode with no known (or zero) duration.
    static func carPlayDuration(_ duration: TimeInterval?) -> String {
        guard let duration, duration > 0 else { return "" }
        let totalMinutes = Int(duration.rounded()) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        guard hours > 0 else { return "\(minutes) min" }
        return "\(hours) hr \(minutes) min"
    }

    /// `queue`, mapped through `carPlayQueueRows(queue:podcasts:)`.
    var carPlayQueueRows: [CarPlayEpisodeRow] {
        Self.carPlayQueueRows(queue: queue, podcasts: podcasts)
    }

    /// `podcasts`, mapped through `carPlayLibraryRows(podcasts:)`.
    var carPlayLibraryRows: [CarPlayPodcastRow] {
        Self.carPlayLibraryRows(podcasts: podcasts)
    }

    /// `podcastID`'s latest 50 episodes (`Store.episodes(podcastID:limit:)`'s own newest-first
    /// order), mapped through `carPlayEpisodeRows(_:)`. Empty while `launchState` isn't `.ready`
    /// or the read fails.
    func carPlayEpisodeRows(podcastID: UUID) async -> [CarPlayEpisodeRow] {
        guard let readyStore else { return [] }
        let episodes = (try? await readyStore.episodes(podcastID: podcastID, limit: 50)) ?? []
        return Self.carPlayEpisodeRows(episodes)
    }
}
