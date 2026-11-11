import Foundation
import JimmyKit
import MediaPlayer
import UIKit

/// Drives everything around `Playback` that used to live in `AudioPlayerService`: Now Playing
/// (title/show/artwork/elapsed/duration/rate), listening stats, the widget's and watch's copies of
/// what's playing, and `lastPlayingEpisodeID` for restore-on-launch. (The audio session itself is
/// activated once, at launch — see `AppModel.open`.) All of it is driven from one
/// `withObservationTracking` loop on `playback`'s observable state — the same pattern
/// `StandardTabBarController` already uses for shell/chrome state, since `Playback` is `@Observable`,
/// not an `ObservableObject` Combine can subscribe to.
extension AppModel {
    /// Loads `episode` into `Playback` (which resolves a downloaded local file over its remote URL
    /// itself — see `playback.resolveAudioURL`), and moves it to queue position 1 — the same
    /// "resume/play now always goes to the front of the queue" behavior `AudioPlayerService
    /// .loadEpisode` applied.
    func play(_ episode: JimmyKit.Episode, startPlaying: Bool = true) async {
        guard let playback else { return }
        await ensureEpisodeIsSaved(episode)
        await playback.load(episode: episode, startPlaying: startPlaying)
        await enqueue(episode.id, at: 1)
    }

    /// Upserts `episode` first when it isn't in the database yet — e.g. a Discover preview episode
    /// the user taps play on before ever subscribing — the way `AudioPlayerService.loadEpisode`
    /// did. Without this, the `progress`/`queue` tables' foreign keys against `episodes` silently
    /// fail (every write here goes through `try?`), so nothing — position, queue membership,
    /// restore-on-launch — persists for it.
    ///
    /// Not `private`: `DemoLibrary.seed(into:)` calls this too, for every episode it queues (not
    /// just the one it plays) — the Queue screen still resolves queued episodes through this same
    /// legacy repository (see `QueueView`'s doc comment), so a demo episode never saved here would
    /// never show up there.
    func ensureEpisodeIsSaved(_ episode: JimmyKit.Episode) async {
        guard let podcastID = episode.podcastID else { return }
        guard (try? await DIContainer.shared.episodeRepository.fetchEpisode(by: episode.id)) == nil else { return }
        let placeholder = EpisodeWithPlaybackState(
            episode: episode.asLegacyEpisode(),
            playbackState: PlaybackState(episodeID: episode.id, position: 0, finished: false)
        )
        try? await DIContainer.shared.episodeRepository.saveEpisodes([placeholder], for: podcastID)
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

        // Also log the listening session so far, restarting it right away if still playing — a
        // kill while backgrounded shouldn't lose time played before the kill.
        if playback.isPlaying {
            flushListeningSession()
            startListeningSession(podcastID: playback.currentEpisode?.podcastID)
        }
    }

    func startObservingPlaybackIfReady() {
        guard case .ready(let ready) = launchState else { return }
        // Clears `lastPlayingEpisodeID` the moment an episode finishes — whether or not there was
        // a next one to advance to — instead of leaving it pointing at an already-finished episode
        // until something else happens to overwrite it (which is what let a finished last-in-queue
        // episode get re-enqueued by `restoreLastEpisodeIfEnabled` on the next launch).
        ready.playback.onEpisodeFinished = { [weak self] episodeID in
            guard let self else { return }
            if self.lastObservedEpisodeID == episodeID {
                self.lastObservedEpisodeID = nil
            }
            if UserDefaults.standard.string(forKey: "lastPlayingEpisodeID") == episodeID.uuidString {
                UserDefaults.standard.removeObject(forKey: "lastPlayingEpisodeID")
            }
        }
        observePlaybackSideEffects(ready)
    }

    private func observePlaybackSideEffects(_ ready: Ready) {
        withObservationTracking { [weak self] in
            _ = self?.playback?.currentEpisode
            _ = self?.playback?.isPlaying
            _ = self?.playback?.duration
            _ = self?.playback?.rate
            // Not `position` itself: it ticks once a second while playing, far too often to drive
            // this loop from. `seekCount` instead reports exactly when the user jumped to a new
            // position (seek/skip/chapter-skip) — see `syncNowPlaying`, which reads `position` only
            // once `handlePlaybackSideEffects` has already decided to run.
            _ = self?.playback?.seekCount
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

        if playback.isPlaying != lastObservedIsPlaying {
            if playback.isPlaying {
                startListeningSession(podcastID: playback.currentEpisode?.podcastID)
            } else {
                flushListeningSession()
            }
            lastObservedIsPlaying = playback.isPlaying
        }

        if let episode = playback.currentEpisode, episode.id != lastObservedEpisodeID {
            lastObservedEpisodeID = episode.id
            UserDefaults.standard.set(episode.id.uuidString, forKey: "lastPlayingEpisodeID")
            recordRecentlyPlayed(episode)
        }

        syncNowPlaying(ready)

        Task { @MainActor in await SharedDataStore.shared.updateWidgetData() }

        pushWatchState()
    }

    private func syncNowPlaying(_ ready: Ready) {
        let playback = ready.playback
        guard let episode = playback.currentEpisode else {
            ready.nowPlaying.clear()
            return
        }

        let podcast = podcasts.first { $0.id == episode.podcastID }
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
