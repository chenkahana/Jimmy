import Foundation
import Testing
@testable import JimmyKit

@MainActor
struct SkipSilenceTests {
    private func makePlayback(
        ranges: [SilenceRange],
        enabled: Bool
    ) async -> (Playback, FakePlayerEngine, Episode) {
        let engine = FakePlayerEngine()
        let playback = Playback(engine: engine, progressStore: FakeProgressStore(), queueSource: FakeQueueSource(), clock: FakeClock())
        playback.silenceRangesProvider = { _ in ranges }
        playback.setSkipSilence(enabled)
        let episode = Episode(title: "Test Episode", audioURL: URL(string: "https://example.com/audio.mp3"), duration: 1_000)
        await playback.load(episode: episode, startPlaying: true)
        return (playback, engine, episode)
    }

    @Test func offByDefault() {
        let playback = Playback(engine: FakePlayerEngine(), progressStore: FakeProgressStore(), queueSource: FakeQueueSource(), clock: FakeClock())
        #expect(playback.skipSilenceEnabled == false)
        #expect(playback.timeSaved == 0)
    }

    @Test func skipsToTheEndOfARangeAndCountsTheTimeSaved() async {
        let (playback, engine, _) = await makePlayback(ranges: [SilenceRange(start: 10, end: 12)], enabled: true)
        await engine.simulateTimeUpdate(10.5)
        #expect(engine.seekedTimes.last == 12)
        #expect(playback.position == 12)
        #expect(abs(playback.timeSaved - 1.5) < 0.0001)
    }

    @Test func doesNothingWhenSwitchedOff() async {
        let (playback, engine, _) = await makePlayback(ranges: [SilenceRange(start: 10, end: 12)], enabled: false)
        await engine.simulateTimeUpdate(10.5)
        #expect(engine.seekedTimes.isEmpty)
        #expect(playback.position == 10.5)
        #expect(playback.timeSaved == 0)
    }

    @Test func doesNothingOutsideAnyRange() async {
        let (playback, engine, _) = await makePlayback(ranges: [SilenceRange(start: 10, end: 12)], enabled: true)
        await engine.simulateTimeUpdate(9)
        await engine.simulateTimeUpdate(12)
        #expect(engine.seekedTimes.isEmpty)
        #expect(playback.timeSaved == 0)
    }

    @Test func doesNotSkipWhilePaused() async {
        let (playback, engine, _) = await makePlayback(ranges: [SilenceRange(start: 10, end: 12)], enabled: true)
        await playback.pause()
        await engine.simulateTimeUpdate(10.5)
        #expect(engine.seekedTimes.isEmpty)
    }

    @Test func aSkipIsNotAUserSeek() async {
        let (playback, engine, _) = await makePlayback(ranges: [SilenceRange(start: 10, end: 12)], enabled: true)
        let before = playback.seekCount
        await engine.simulateTimeUpdate(10.5)
        #expect(playback.seekCount == before)
    }

    @Test func rangesForAnotherEpisodeAreIgnored() async {
        let (playback, _, _) = await makePlayback(ranges: [], enabled: true)
        playback.setSilenceRanges([SilenceRange(start: 1, end: 2)], for: UUID())
        #expect(playback.silenceRanges.isEmpty)
    }
}
