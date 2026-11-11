import Foundation
import Testing
@testable import JimmyKit

@MainActor
struct SaveThrottlingTests {
    private func makeEpisode() -> Episode {
        Episode(title: "Test Episode", audioURL: URL(string: "https://example.com/audio.mp3"), duration: 1_000)
    }

    @Test func savesAtMostOncePerFiveSecondsWhilePlaying() async {
        let engine = FakePlayerEngine()
        let progressStore = FakeProgressStore()
        let clock = FakeClock()
        let playback = Playback(engine: engine, progressStore: progressStore, queueSource: FakeQueueSource(), clock: clock)

        await playback.load(episode: makeEpisode())
        #expect(progressStore.savedProgresses.isEmpty)

        playback.play()

        await engine.simulateTimeUpdate(1)
        #expect(progressStore.savedProgresses.count == 1, "first update while playing saves immediately")

        clock.advance(by: 2)
        await engine.simulateTimeUpdate(3)
        #expect(progressStore.savedProgresses.count == 1, "within 5s of the last save, no new save")

        clock.advance(by: 3)
        await engine.simulateTimeUpdate(6)
        #expect(progressStore.savedProgresses.count == 2, "5s elapsed since the last save, saves again")
    }

    @Test func doesNotSaveFromTimeUpdatesWhilePaused() async {
        let engine = FakePlayerEngine()
        let progressStore = FakeProgressStore()
        let playback = Playback(engine: engine, progressStore: progressStore, queueSource: FakeQueueSource())

        await playback.load(episode: makeEpisode())
        await engine.simulateTimeUpdate(1)

        #expect(progressStore.savedProgresses.isEmpty)
    }

    @Test func pauseSeekAndFlushEachSaveImmediatelyRegardlessOfThrottle() async {
        let engine = FakePlayerEngine()
        let progressStore = FakeProgressStore()
        let playback = Playback(engine: engine, progressStore: progressStore, queueSource: FakeQueueSource())

        await playback.load(episode: makeEpisode(), startPlaying: true)

        await playback.pause()
        #expect(progressStore.savedProgresses.count == 1)

        await playback.seek(to: 10)
        #expect(progressStore.savedProgresses.count == 2)

        await playback.flush()
        #expect(progressStore.savedProgresses.count == 3)
    }
}
