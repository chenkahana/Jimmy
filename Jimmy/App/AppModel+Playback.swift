import Foundation
import JimmyKit
import MediaPlayer
import UIKit

/// Drives everything around `Playback` that used to live in `AudioPlayerService`: Now Playing
/// (title/show/artwork/elapsed/duration/rate), the audio session's first activation, listening
/// stats, the widget's and watch's copies of what's playing, and `lastPlayingEpisodeID` for
/// restore-on-launch. All of it is driven from one `withObservationTracking` loop on `playback`'s
/// observable state — the same pattern `StandardTabBarController` already uses for shell/chrome
/// state, since `Playback` is `@Observable`, not an `ObservableObject` Combine can subscribe to.
extension AppModel {
    /// Loads `episode` into `Playback`, preferring a downloaded local file over its remote URL,
    /// and moves it to queue position 1 — the same "resume/play now always goes to the front of
    /// the queue" behavior `AudioPlayerService.loadEpisode` applied.
    func play(_ episode: JimmyKit.Episode, startPlaying: Bool = true) async {
        guard let playback else { return }
        let url = DownloadManager.shared.effectiveURL(forEpisodeID: episode.id, remoteURL: episode.audioURL)
        await playback.load(episode: episode, startPlaying: startPlaying, audioURLOverride: url)
        await enqueue(episode.id, at: 1)
    }

    /// Restores whatever was last playing, paused, the way `AudioPlayerService` did at launch.
    /// Call once, after `SettingsViewModel` has written its `autoRestoreLastEpisode` default.
    func restoreLastEpisodeIfEnabled() async {
        guard UserDefaults.standard.bool(forKey: "autoRestoreLastEpisode") else { return }
        guard let episodeIDString = UserDefaults.standard.string(forKey: "lastPlayingEpisodeID"),
              let episodeID = UUID(uuidString: episodeIDString) else { return }
        guard let episodeWithState = try? await DIContainer.shared.episodeRepository.fetchEpisode(by: episodeID) else { return }
        await play(episodeWithState.episode.asPlaybackEpisode(), startPlaying: false)
    }

    /// Updates both the in-memory skip intervals `Playback.skipForward()`/`skipBackward()` use and
    /// the lock-screen/Control-Center intervals, together — call when the user changes the
    /// Settings skip-duration pickers.
    func updateSkipIntervals(forward: TimeInterval, backward: TimeInterval) {
        guard case .ready(let ready) = launchState else { return }
        ready.playback.skipForwardInterval = forward
        ready.playback.skipBackwardInterval = backward
        ready.remoteCommands.updateSkipIntervals(forward: forward, backward: backward)
    }

    /// Flushes the current position immediately. Call when the app is about to enter the
    /// background (`JimmyApp`'s `scenePhase` handling) — `Playback`'s own saves are throttled.
    func flushPlaybackForBackground() {
        guard let playback else { return }
        Task { await playback.flush() }
    }

    func startObservingPlaybackIfReady() {
        guard case .ready(let ready) = launchState else { return }
        observePlaybackSideEffects(ready)
    }

    private func observePlaybackSideEffects(_ ready: Ready) {
        withObservationTracking { [weak self] in
            _ = self?.playback?.currentEpisode
            _ = self?.playback?.isPlaying
            _ = self?.playback?.duration
            _ = self?.playback?.rate
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handlePlaybackSideEffects(ready)
                self.observePlaybackSideEffects(ready)
            }
        }
        handlePlaybackSideEffects(ready)
    }

    private func handlePlaybackSideEffects(_ ready: Ready) {
        let playback = ready.playback

        if playback.isPlaying {
            try? ready.audioSession.activate()
        }

        if playback.isPlaying != lastObservedIsPlaying {
            if playback.isPlaying {
                ListeningStatsService.shared.startTracking(podcastID: playback.currentEpisode?.podcastID?.uuidString)
            } else {
                ListeningStatsService.shared.stopTracking()
            }
            lastObservedIsPlaying = playback.isPlaying
        }

        if let episodeID = playback.currentEpisode?.id, episodeID != lastObservedEpisodeID {
            lastObservedEpisodeID = episodeID
            UserDefaults.standard.set(episodeID.uuidString, forKey: "lastPlayingEpisodeID")
        }

        syncNowPlaying(ready)

        Task { @MainActor in await SharedDataStore.shared.updateWidgetData() }

        WatchConnectivityService.shared.sendPlaybackUpdate(
            episode: playback.currentEpisode?.asLegacyEpisode(),
            isPlaying: playback.isPlaying,
            position: playback.position,
            duration: playback.duration ?? 0
        )
    }

    private func syncNowPlaying(_ ready: Ready) {
        let playback = ready.playback
        guard let episode = playback.currentEpisode else {
            ready.nowPlaying.clear()
            return
        }

        let podcast = PodcastService.shared.loadPodcasts().first { $0.id == episode.podcastID }
        ready.nowPlaying.update(
            title: episode.title,
            podcastTitle: podcast?.title,
            duration: playback.duration,
            elapsed: playback.position,
            rate: playback.isPlaying ? playback.rate : 0,
            artwork: nowPlayingArtworkCache[episode.id]
        )

        guard nowPlayingArtworkCache[episode.id] == nil,
              let artworkURL = episode.artworkURL ?? podcast?.artworkURL else { return }
        Task { [weak self] in
            guard let image = await Self.loadArtworkImage(from: artworkURL) else { return }
            await MainActor.run {
                guard let self, self.playback?.currentEpisode?.id == episode.id else { return }
                self.nowPlayingArtworkCache[episode.id] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.syncNowPlaying(ready)
            }
        }
    }

    private static func loadArtworkImage(from url: URL) async -> UIImage? {
        let request = URLRequest(url: url, timeoutInterval: 5.0)
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return UIImage(data: data)
    }
}
