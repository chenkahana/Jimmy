import Foundation
import Testing
@testable import JimmyKit

@MainActor
struct SleepTimerTests {
    private func makeEpisode(title: String = "A") -> Episode {
        Episode(title: title, audioURL: URL(string: "https://example.com/\(title).mp3"), duration: 1_000)
    }

    @Test func durationTimerCountsDownAndFiresAfterItElapses() async {
        let engine = FakePlayerEngine()
        let clock = FakeClock()
        let playback = Playback(engine: engine, progressStore: FakeProgressStore(), queueSource: FakeQueueSource(), clock: clock)
        await playback.load(episode: makeEpisode(), startPlaying: true)

        playback.startSleepTimer(.duration(5))
        #expect(playback.sleepTimerMode == .duration(5))

        clock.advance(by: 3)
        await engine.simulateTimeUpdate(10)
        #expect(playback.sleepTimerRemaining == 2)
        #expect(playback.isPlaying == true, "timer hasn't elapsed yet")

        clock.advance(by: 3)
        await engine.simulateTimeUpdate(13)
        #expect(playback.isPlaying == false, "timer elapsed, playback pauses")
        #expect(playback.sleepTimerMode == nil, "the timer clears itself once fired")
    }

    @Test func cancelSleepTimerStopsIt() async {
        let engine = FakePlayerEngine()
        let clock = FakeClock()
        let playback = Playback(engine: engine, progressStore: FakeProgressStore(), queueSource: FakeQueueSource(), clock: clock)
        await playback.load(episode: makeEpisode(), startPlaying: true)

        playback.startSleepTimer(.duration(5))
        playback.cancelSleepTimer()

        clock.advance(by: 10)
        await engine.simulateTimeUpdate(10)

        #expect(playback.isPlaying == true)
        #expect(playback.sleepTimerMode == nil)
    }

    @Test func endOfEpisodeModePausesAtEndOfItemWithoutAutoAdvancing() async {
        let engine = FakePlayerEngine()
        let queueSource = FakeQueueSource()
        let episodeA = makeEpisode(title: "A")
        let episodeB = makeEpisode(title: "B")
        queueSource.queue = [episodeB]

        let playback = Playback(engine: engine, progressStore: FakeProgressStore(), queueSource: queueSource)
        await playback.load(episode: episodeA, startPlaying: true)
        playback.startSleepTimer(.endOfEpisode)

        await engine.simulateEndOfItem()

        #expect(playback.isPlaying == false)
        #expect(playback.sleepTimerMode == nil)
        #expect(playback.currentEpisode == episodeA, "end-of-episode sleep mode stops instead of advancing")
        // The episode did finish, so it's marked finished and leaves the queue.
        #expect(queueSource.removedIDs == [episodeA.id])
    }
}
