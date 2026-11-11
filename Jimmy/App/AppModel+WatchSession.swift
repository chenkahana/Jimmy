import Foundation
import JimmyKit

/// The phone side of the watch app's connectivity: builds the `WatchSessionState` pushed to the
/// watch (`WatchConnectivityService.update`, called whenever `playback` or the queue changes — see
/// `AppModel+Playback.swift` and `startObservingQueueIfReady()`), and applies the `WatchCommand`s
/// the watch sends back through the same methods a tap in the phone's own UI would use.
extension AppModel {
    /// Applies a command the watch sent.
    func apply(_ watchCommand: WatchCommand) async {
        switch watchCommand {
        case .play:
            playback?.play()
        case .pause:
            await playback?.pause()
        case .skipForward:
            await playback?.skipForward()
        case .skipBackward:
            await playback?.skipBackward()
        case .playEpisode(let episodeID):
            await playEpisodeKnownToWatch(episodeID)
        case .removeFromQueue(let episodeID):
            await dequeue(episodeID)
        }
    }

    /// Pushes the watch's whole state to `WatchConnectivityService`.
    func pushWatchState() {
        WatchConnectivityService.shared.update(watchState())
    }

    /// The watch's current state, built from `playback`, `queue` and `recentlyPlayedEpisodes`.
    /// Also answers the watch's own request for the current state directly (see
    /// `WatchConnectivityService`), so a freshly-launched watch app doesn't have to wait for the
    /// next playback or queue change.
    func watchState() -> WatchSessionState {
        var nowPlaying: WatchNowPlaying?
        if let playback, let episode = playback.currentEpisode {
            nowPlaying = WatchNowPlaying(
                episodeID: episode.id,
                title: episode.title,
                showTitle: podcastTitle(for: episode.podcastID),
                artworkURL: episode.artworkURL,
                position: playback.position,
                duration: playback.duration,
                isPlaying: playback.isPlaying,
                rate: playback.rate
            )
        }
        return WatchSessionState(
            nowPlaying: nowPlaying,
            queue: queue.map(watchSummary),
            recent: recentlyPlayedEpisodes.map(watchSummary)
        )
    }

    /// Only plays `episodeID` from the watch when it's an episode the watch was actually shown —
    /// the current queue or recent list — since the watch never has an arbitrary episode id of
    /// its own to send.
    private func playEpisodeKnownToWatch(_ episodeID: UUID) async {
        guard let episode = queue.first(where: { $0.id == episodeID })
            ?? recentlyPlayedEpisodes.first(where: { $0.id == episodeID }) else { return }
        await play(episode)
    }

    private func watchSummary(_ episode: JimmyKit.Episode) -> WatchEpisodeSummary {
        WatchEpisodeSummary(id: episode.id, title: episode.title, showTitle: podcastTitle(for: episode.podcastID))
    }

    private func podcastTitle(for podcastID: UUID?) -> String? {
        guard let podcastID else { return nil }
        return podcasts.first { $0.id == podcastID }?.title
    }

    /// Records `episode` at the front of `recentlyPlayedEpisodes` (deduplicated, capped at
    /// `WatchSessionState.maxRecentCount`). Called from `handlePlaybackSideEffects` whenever the
    /// current episode changes.
    func recordRecentlyPlayed(_ episode: JimmyKit.Episode) {
        recentlyPlayedEpisodes.removeAll { $0.id == episode.id }
        recentlyPlayedEpisodes.insert(episode, at: 0)
        if recentlyPlayedEpisodes.count > WatchSessionState.maxRecentCount {
            recentlyPlayedEpisodes.removeLast(recentlyPlayedEpisodes.count - WatchSessionState.maxRecentCount)
        }
    }
}
