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

    // MARK: - Configuration

    public var skipForwardInterval: TimeInterval
    public var skipBackwardInterval: TimeInterval

    /// Minimum spacing between throttled position saves while playing.
    public static let saveInterval: TimeInterval = 5

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
    public func load(episode: Episode, chapters: [Chapter] = [], startPlaying: Bool = false) async {
        await flush()

        let progress = await progressStore.loadProgress(for: episode.id)

        currentEpisode = episode
        self.chapters = chapters
        // A finished episode starts over instead of ending as soon as it loads.
        position = progress?.isFinished == true ? 0 : (progress?.position ?? 0)
        duration = progress?.duration ?? episode.duration
        lastSaveAt = nil
        updateCurrentChapter()

        guard let url = episode.audioURL else {
            isPlaying = false
            return
        }

        engine.load(url: url)
        engine.rate = rate
        if position > 0 {
            engine.seek(to: position)
        }

        if startPlaying {
            play()
        } else {
            isPlaying = false
        }
    }

    // MARK: - Transport

    public func play() {
        guard currentEpisode != nil else { return }
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

    public func seek(to time: TimeInterval) async {
        let clamped = clampedPosition(time)
        engine.seek(to: clamped)
        position = clamped
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

        let finishedProgress = Progress(
            episodeID: episode.id,
            position: duration ?? position,
            duration: duration,
            isFinished: true,
            updatedAt: clock.now()
        )
        await progressStore.saveProgress(finishedProgress)
        await queueSource.removeFinished(episode.id)

        if advance, let next = await queueSource.episode(after: episode.id) {
            await load(episode: next, startPlaying: true)
        }
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
        }
    }
}
