import Foundation
import Observation

/// Bounds for `Playback.setRate`.
public enum PlaybackSpeed {
    public static let min: Float = 0.5
    public static let max: Float = 3.0
}

/// A sleep timer mode: stop after a fixed duration, or stop at the end of the current episode.
public nonisolated enum SleepTimerMode: Sendable, Equatable {
    case duration(TimeInterval)
    case endOfEpisode
}

/// Owns playback of a single episode at a time: the underlying `PlayerEngine`, saved-position
/// bookkeeping, finished/auto-advance, sleep timer, and chapter navigation.
///
/// Collaborators (`PlayerEngine`, `ProgressStore`, `QueueSource`, `Clock`) are protocols so this
/// type can be driven entirely by fakes in tests, with no real `AVPlayer`/`AVAudioSession`/database
/// involved. Methods that persist to the store (`pause`, `seek`, `flush`, skip, chapter-skip,
/// `advanceToNextEpisode`, `load`) are `async` so callers — and tests — can await the save
/// completing, instead of this type spawning untracked background work for it.
@Observable
public final class Playback {
    // MARK: - Observable state

    public private(set) var currentEpisode: Episode?
    public private(set) var isPlaying: Bool = false
    public private(set) var position: TimeInterval = 0
    public private(set) var duration: TimeInterval?
    public private(set) var rate: Float = 1.0
    public private(set) var currentChapter: Chapter?
    public private(set) var sleepTimerMode: SleepTimerMode?
    public private(set) var sleepTimerRemaining: TimeInterval?
    /// Bumped on every `seek(to:)` (including skip/chapter-skip, which call it). `Playback`'s
    /// position itself ticks once a second while playing and is too noisy to drive Now Playing
    /// from directly; observing this instead lets a caller learn exactly when the user jumped to
    /// a new position, distinct from the engine's own ongoing playback ticks.
    public private(set) var seekCount = 0

    // MARK: - Configuration

    public var skipForwardInterval: TimeInterval
    public var skipBackwardInterval: TimeInterval

    /// Resolves the URL to actually play for an episode — e.g. substituting a downloaded file's
    /// local URL for its remote one. Defaults to the episode's own `audioURL`. Applied on every
    /// `load()`, including auto-advance and the remote "next track" command, not just a caller's
    /// direct `load` — so a downloaded episode plays from disk no matter how playback reaches it.
    public var resolveAudioURL: (Episode) -> URL? = { $0.audioURL }

    /// Called with the id of an episode that just finished (crossed `Progress.finishedThreshold`),
    /// whether or not there was a next episode to advance to. Not called on an ordinary pause/stop.
    /// The default is a no-op; `AppModel` uses it to clear `lastPlayingEpisodeID` immediately on
    /// finish, the way the old service did, instead of leaving it pointing at an episode that's
    /// already done until something else happens to overwrite it.
    public var onEpisodeFinished: (UUID) -> Void = { _ in }

    /// Minimum spacing between throttled position saves while playing.
    public static let saveInterval: TimeInterval = 5

    /// How long before a `.duration` sleep timer fires that volume starts fading to 0.
    public static let sleepTimerFadeOutDuration: TimeInterval = 30

    // MARK: - Collaborators

    private let engine: PlayerEngine
    private let progressStore: ProgressStore
    private let queueSource: QueueSource
    private let clock: Clock

    // MARK: - Private state

    private var chapters: [Chapter] = []
    private var lastSaveAt: Date?
    private var sleepTimerEndDate: Date?

    public init(
        engine: PlayerEngine,
        progressStore: ProgressStore,
        queueSource: QueueSource,
        clock: Clock = SystemClock(),
        skipForwardInterval: TimeInterval = 15,
        skipBackwardInterval: TimeInterval = 15
    ) {
        self.engine = engine
        self.progressStore = progressStore
        self.queueSource = queueSource
        self.clock = clock
        self.skipForwardInterval = skipForwardInterval
        self.skipBackwardInterval = skipBackwardInterval

        engine.onTimeUpdate = { [weak self] time in await self?.handleTimeUpdate(time) }
        engine.onDurationAvailable = { [weak self] newDuration in self?.handleDurationAvailable(newDuration) }
        engine.onEndOfItem = { [weak self] in await self?.handleEndOfItem() }
    }

    // MARK: - Loading

    /// Load `episode` for playback, restoring saved progress and optionally starting playback.
    /// Flushes any pending save for the previously-loaded episode first.
    ///
    /// Resumes at `progress.position` unconditionally — an episode only starts over at 0:00 when
    /// it actually just finished, because `finishCurrentEpisode` saves its position as 0. (An
    /// episode merely in its last few percent, or one the legacy "played" flag was set on by the
    /// one-time migration, keeps its saved position instead of restarting.)
    public func load(
        episode: Episode,
        chapters: [Chapter] = [],
        startPlaying: Bool = false
    ) async {
        await flush()

        let progress = await progressStore.loadProgress(for: episode.id)

        currentEpisode = episode
        self.chapters = chapters
        position = progress?.position ?? 0
        duration = progress?.duration ?? episode.duration
        lastSaveAt = nil
        updateCurrentChapter()

        guard let url = resolveAudioURL(episode) else {
            isPlaying = false
            return
        }

        // The engine defers actually seeking to `position` until the item reports ready, instead
        // of `Playback` seeking here immediately: a seek issued before that silently drops, and an
        // `onTimeUpdate` tick that arrives before it lands would otherwise report (and get saved
        // as) position 0, overwriting the real saved position.
        engine.load(url: url, startPosition: position)
        engine.rate = rate

        if startPlaying {
            play()
        } else {
            isPlaying = false
        }
    }

    // MARK: - Transport

    public func play() {
        guard currentEpisode != nil else { return }
        // A `.duration` timer that elapsed while paused shouldn't immediately re-pause what the
        // user just explicitly resumed; quietly drop it instead; the end-of-episode variant has no
        // end date to go stale this way.
        if let sleepTimerEndDate, sleepTimerEndDate <= clock.now() {
            cancelSleepTimer()
        }
        engine.rate = rate
        engine.play()
        isPlaying = true
    }

    public func pause() async {
        engine.pause()
        isPlaying = false
        await flush()
    }

    public func togglePlayPause() async {
        if isPlaying {
            await pause()
        } else {
            play()
        }
    }

    /// Unload the current episode entirely: flushes its position, pauses the engine, and clears
    /// `currentEpisode` (so Now Playing and the mini player stop showing it). Used when whatever's
    /// playing is no longer available (e.g. its podcast was unsubscribed) — unlike `pause()`,
    /// which keeps `currentEpisode` so playback can resume.
    public func stop() async {
        await flush()
        engine.pause()
        isPlaying = false
        currentEpisode = nil
        position = 0
        duration = nil
        chapters = []
        currentChapter = nil
        cancelSleepTimer()
    }

    public func seek(to time: TimeInterval) async {
        let clamped = clampedPosition(time)
        engine.seek(to: clamped)
        position = clamped
        seekCount += 1
        updateCurrentChapter()
        await flush()
    }

    public func skipForward() async {
        await seek(to: position + skipForwardInterval)
    }

    public func skipBackward() async {
        await seek(to: position - skipBackwardInterval)
    }

    /// Set playback speed, clamped to `PlaybackSpeed.min...max`.
    public func setRate(_ newRate: Float) {
        rate = min(PlaybackSpeed.max, max(PlaybackSpeed.min, newRate))
        engine.rate = rate
    }

    /// Move to the next queued episode without marking the current one finished.
    /// Used for the remote "next track" command; the current episode keeps its position and queue place.
    public func advanceToNextEpisode() async {
        guard let episode = currentEpisode, let next = await queueSource.episode(after: episode.id) else { return }
        await load(episode: next, startPlaying: isPlaying)
    }

    /// Save the current position immediately, bypassing the throttle. Call on pause, seek,
    /// episode change, and when the app is about to enter the background.
    public func flush() async {
        guard let episode = currentEpisode else { return }
        let now = clock.now()
        lastSaveAt = now
        await persist(episodeID: episode.id, at: now)
    }

    // MARK: - Sleep timer

    public func startSleepTimer(_ mode: SleepTimerMode) {
        sleepTimerMode = mode
        switch mode {
        case .duration(let seconds):
            sleepTimerEndDate = clock.now().addingTimeInterval(seconds)
            sleepTimerRemaining = seconds
        case .endOfEpisode:
            sleepTimerEndDate = nil
            sleepTimerRemaining = nil
        }
    }

    public func cancelSleepTimer() {
        sleepTimerMode = nil
        sleepTimerEndDate = nil
        sleepTimerRemaining = nil
        engine.volume = 1.0
    }

    /// Push a running `.duration` timer's end date back by `seconds`. A no-op without an active
    /// `.duration` timer (there's no end date to extend for `.endOfEpisode`).
    public func extendSleepTimer(by seconds: TimeInterval) {
        guard let sleepTimerEndDate else { return }
        self.sleepTimerEndDate = sleepTimerEndDate.addingTimeInterval(seconds)
        sleepTimerRemaining = self.sleepTimerEndDate?.timeIntervalSince(clock.now())
    }

    // MARK: - Chapters

    public func nextChapter() -> Chapter? {
        guard !chapters.isEmpty else { return nil }
        guard let current = currentChapter, let index = chapters.firstIndex(of: current) else {
            return chapters.first
        }
        let nextIndex = index + 1
        return nextIndex < chapters.count ? chapters[nextIndex] : nil
    }

    public func previousChapter() -> Chapter? {
        guard !chapters.isEmpty else { return nil }
        guard let current = currentChapter, let index = chapters.firstIndex(of: current) else {
            return nil
        }
        return index > 0 ? chapters[index - 1] : nil
    }

    public func skipToNextChapter() async {
        if let next = nextChapter() { await seek(to: next.start) }
    }

    public func skipToPreviousChapter() async {
        if let previous = previousChapter() { await seek(to: previous.start) }
    }

    // MARK: - Engine callbacks

    private func handleTimeUpdate(_ time: TimeInterval) async {
        position = time
        updateCurrentChapter()
        await checkSleepTimer()
        await throttledSave()
    }

    private func handleDurationAvailable(_ newDuration: TimeInterval) {
        duration = newDuration
    }

    private func handleEndOfItem() async {
        guard currentEpisode != nil else { return }

        isPlaying = false
        if sleepTimerMode == .endOfEpisode {
            cancelSleepTimer()
            engine.pause()
            await finishCurrentEpisode(thenAdvance: false)
            return
        }

        await finishCurrentEpisode(thenAdvance: true)
    }

    // MARK: - Helpers

    private func finishCurrentEpisode(thenAdvance advance: Bool) async {
        guard let episode = currentEpisode else { return }

        // Matches the old service: a finished episode's saved position resets to 0, so it starts
        // over next time rather than reopening at the end.
        let finishedProgress = Progress(
            episodeID: episode.id,
            position: 0,
            duration: duration,
            isFinished: true,
            updatedAt: clock.now()
        )
        await progressStore.saveProgress(finishedProgress)
        await queueSource.removeFinished(episode.id)
        onEpisodeFinished(episode.id)

        guard advance, let next = await queueSource.episode(after: episode.id) else { return }

        // Clear `currentEpisode` before `load(next)`: its own initial `flush()` reads
        // `currentEpisode`, and if it still pointed at the episode that just finished, it would
        // recompute and persist that episode's `isFinished` from the live `position`/`duration` —
        // overwriting the just-saved finished row with `isFinished: false` whenever `duration`
        // isn't known, or `position` hadn't caught up to it yet (as in the common case here, where
        // the end-of-item position is still whatever it was before this method zeroed it).
        currentEpisode = nil
        await load(episode: next, startPlaying: true)
    }

    private func clampedPosition(_ time: TimeInterval) -> TimeInterval {
        var clamped = max(0, time)
        if let duration, duration > 0 {
            clamped = min(clamped, duration)
        }
        return clamped
    }

    private func updateCurrentChapter() {
        currentChapter = chapters.last(where: { $0.start <= position })
    }

    private func throttledSave() async {
        guard isPlaying, let episode = currentEpisode else { return }
        let now = clock.now()
        if let lastSaveAt, now.timeIntervalSince(lastSaveAt) < Self.saveInterval { return }
        lastSaveAt = now
        await persist(episodeID: episode.id, at: now)
    }

    private func persist(episodeID: UUID, at date: Date) async {
        let finished = Progress.isFinished(position: position, duration: duration)
        let progress = Progress(
            episodeID: episodeID,
            position: position,
            duration: duration,
            isFinished: finished,
            updatedAt: date
        )
        await progressStore.saveProgress(progress)
    }

    private func checkSleepTimer() async {
        guard let endDate = sleepTimerEndDate else { return }
        let remaining = endDate.timeIntervalSince(clock.now())
        if remaining <= 0 {
            cancelSleepTimer()
            await pause()
        } else {
            sleepTimerRemaining = remaining
            if remaining <= Self.sleepTimerFadeOutDuration {
                engine.volume = Float(remaining / Self.sleepTimerFadeOutDuration)
            }
        }
    }
}
