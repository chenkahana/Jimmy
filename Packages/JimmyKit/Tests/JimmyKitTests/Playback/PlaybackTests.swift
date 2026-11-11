import Foundation
import Testing
@testable import JimmyKit

@MainActor
struct PlaybackTests {
    private func makeEpisode(duration: TimeInterval? = 1_000) -> Episode {
        Episode(title: "Test Episode", audioURL: URL(string: "https://example.com/audio.mp3"), duration: duration)
    }

    private func makeSUT(
        progressStore: FakeProgressStore = FakeProgressStore(),
        queueSource: FakeQueueSource = FakeQueueSource(),
        clock: FakeClock = FakeClock()
    ) -> (Playback, FakePlayerEngine) {
        let engine = FakePlayerEngine()
        let playback = Playback(engine: engine, progressStore: progressStore, queueSource: queueSource, clock: clock)
        return (playback, engine)
    }

    @Test func loadingAnEpisodeLoadsItIntoTheEngine() async {
        let (playback, engine) = makeSUT()
        let episode = makeEpisode()

        await playback.load(episode: episode)

        #expect(engine.loadedURLs == [episode.audioURL])
        #expect(playback.currentEpisode == episode)
        #expect(playback.isPlaying == false)
    }

    /// `resolveAudioURL` is how `AppModel` substitutes a downloaded episode's local file URL for
    /// its remote one, without `Playback` itself knowing anything about downloads. It's a closure
    /// `Playback` consults on every `load`, not a one-off parameter, so it also applies to loads
    /// `AppModel` doesn't directly call — see `autoAdvanceResolvesTheNextEpisodesURLToo` below.
    @Test func loadingAnEpisodeResolvesItsURLThroughResolveAudioURL() async {
        let (playback, engine) = makeSUT()
        let episode = makeEpisode()
        let localURL = URL(fileURLWithPath: "/tmp/downloaded-episode.mp3")
        playback.resolveAudioURL = { _ in localURL }

        await playback.load(episode: episode)

        #expect(engine.loadedURLs == [localURL])
        #expect(playback.currentEpisode == episode)
    }

    @Test func playStartsTheEngineAndSetsIsPlaying() async {
        let (playback, engine) = makeSUT()
        await playback.load(episode: makeEpisode())

        playback.play()

        #expect(engine.playCallCount == 1)
        #expect(playback.isPlaying == true)
    }

    @Test func pauseStopsTheEngineAndClearsIsPlaying() async {
        let (playback, engine) = makeSUT()
        await playback.load(episode: makeEpisode(), startPlaying: true)

        await playback.pause()

        #expect(engine.pauseCallCount == 1)
        #expect(playback.isPlaying == false)
    }

    @Test func seekMovesEngineAndPosition() async {
        let (playback, engine) = makeSUT()
        await playback.load(episode: makeEpisode())

        await playback.seek(to: 42)

        #expect(engine.seekedTimes == [42])
        #expect(playback.position == 42)
    }

    @Test func seekClampsToZeroAndDuration() async {
        let (playback, engine) = makeSUT()
        await playback.load(episode: makeEpisode(duration: 100))

        await playback.seek(to: -10)
        #expect(playback.position == 0)

        await playback.seek(to: 500)
        #expect(playback.position == 100)

        _ = engine
    }

    @Test func skipForwardAndBackwardUseConfiguredIntervals() async {
        let engine = FakePlayerEngine()
        let playback = Playback(
            engine: engine,
            progressStore: FakeProgressStore(),
            queueSource: FakeQueueSource(),
            skipForwardInterval: 30,
            skipBackwardInterval: 10
        )
        await playback.load(episode: makeEpisode(duration: 1_000))
        await playback.seek(to: 100)

        await playback.skipForward()
        #expect(playback.position == 130)

        await playback.skipBackward()
        #expect(playback.position == 120)
    }

    @Test func skipBackwardClampsAtZero() async {
        let (playback, _) = makeSUT()
        await playback.load(episode: makeEpisode())
        await playback.seek(to: 5)

        await playback.skipBackward()

        #expect(playback.position == 0)
    }

    @Test func setRateClampsToConfiguredBounds() async {
        let (playback, engine) = makeSUT()
        await playback.load(episode: makeEpisode())

        playback.setRate(10)
        #expect(playback.rate == PlaybackSpeed.max)
        #expect(engine.rate == PlaybackSpeed.max)

        playback.setRate(0.1)
        #expect(playback.rate == PlaybackSpeed.min)

        playback.setRate(1.75)
        #expect(playback.rate == 1.75)
    }

    @Test func timeUpdatesFromTheEngineUpdatePosition() async {
        let (playback, engine) = makeSUT()
        await playback.load(episode: makeEpisode())

        await engine.simulateTimeUpdate(17)

        #expect(playback.position == 17)
    }

    @Test func durationBecomesAvailableFromTheEngine() async {
        let (playback, engine) = makeSUT()
        await playback.load(episode: makeEpisode(duration: nil))

        engine.simulateDurationAvailable(321)

        #expect(playback.duration == 321)
    }

    @Test func stopFlushesPositionPausesTheEngineAndClearsCurrentEpisode() async {
        let progressStore = FakeProgressStore()
        let (playback, engine) = makeSUT(progressStore: progressStore)
        await playback.load(episode: makeEpisode(), startPlaying: true)
        await playback.seek(to: 55)

        await playback.stop()

        #expect(engine.pauseCallCount == 1)
        #expect(playback.isPlaying == false)
        #expect(playback.currentEpisode == nil)
        #expect(playback.position == 0)
        #expect(playback.duration == nil)
        #expect(progressStore.savedProgresses.last?.position == 55, "flushed the position before clearing it")
    }

    @Test func seekBumpsSeekCountSoNowPlayingCanResyncElapsedTime() async {
        let (playback, _) = makeSUT()
        await playback.load(episode: makeEpisode())
        #expect(playback.seekCount == 0)

        await playback.seek(to: 10)
        #expect(playback.seekCount == 1)

        await playback.skipForward()
        #expect(playback.seekCount == 2)

        await playback.skipBackward()
        #expect(playback.seekCount == 3)
    }

    /// A sleep timer that elapsed while paused shouldn't immediately re-pause what the user just
    /// resumed — it should only ever pause from a tick that arrives while actually playing.
    @Test func resumingAfterASleepTimerElapsedWhilePausedDoesNotImmediatelyRePause() async {
        let clock = FakeClock()
        let (playback, engine) = makeSUT(clock: clock)
        await playback.load(episode: makeEpisode(), startPlaying: true)
        playback.startSleepTimer(.duration(60))

        await playback.pause()
        clock.advance(by: 120) // elapses the timer while paused

        playback.play()

        #expect(playback.isPlaying == true)
        #expect(playback.sleepTimerMode == nil, "the stale timer is cancelled, not re-triggered")
        #expect(engine.pauseCallCount == 1, "only the explicit pause above — resuming didn't pause again")
    }

    // MARK: - S1: don't seek or save before the item is ready

    @Test func loadDefersTheRestoreSeekUntilTheEngineBecomesReady() async {
        let progressStore = FakeProgressStore()
        let episode = makeEpisode()
        await progressStore.saveProgress(Progress(episodeID: episode.id, position: 120, duration: 1_000))
        let (playback, engine) = makeSUT(progressStore: progressStore)
        engine.becomesReadySlowly = true

        await playback.load(episode: episode, startPlaying: true)

        #expect(playback.position == 120, "Playback's own restored position is known immediately")
        #expect(engine.seekedTimes.isEmpty, "but the engine hasn't seeked there yet — it isn't ready")
        #expect(engine.playCallCount == 0, "and hasn't started playing yet either")

        engine.simulateBecomesReady()

        #expect(engine.seekedTimes == [120])
        #expect(engine.playCallCount == 1)
    }

    @Test func aTimeUpdateBeforeTheEngineIsReadyIsIgnoredAndCannotOverwriteTheSavedPosition() async {
        let progressStore = FakeProgressStore()
        let episode = makeEpisode()
        await progressStore.saveProgress(Progress(episodeID: episode.id, position: 120, duration: 1_000))
        let (playback, engine) = makeSUT(progressStore: progressStore)
        engine.becomesReadySlowly = true

        await playback.load(episode: episode, startPlaying: true)
        await engine.simulateTimeUpdate(0) // a stray pre-ready tick, as a real AVPlayer can emit

        #expect(playback.position == 120, "the stray tick before readiness was ignored")
        #expect(progressStore.savedProgresses.last?.position == 120, "and nothing overwrote the saved position")

        engine.simulateBecomesReady()
        await engine.simulateTimeUpdate(125)

        #expect(playback.position == 125, "a tick after readiness is honored normally")
    }
}
