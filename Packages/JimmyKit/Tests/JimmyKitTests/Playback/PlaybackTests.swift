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
}
