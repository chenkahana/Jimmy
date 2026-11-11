import Foundation
import Testing
@testable import JimmyKit

@MainActor
struct FinishedAndAdvanceTests {
    private func makeEpisode(title: String, duration: TimeInterval? = 1_000) -> Episode {
        Episode(title: title, audioURL: URL(string: "https://example.com/\(title).mp3"), duration: duration)
    }

    @Test func crossingNinetyFivePercentMarksProgressFinished() async {
        let engine = FakePlayerEngine()
        let progressStore = FakeProgressStore()
        let playback = Playback(engine: engine, progressStore: progressStore, queueSource: FakeQueueSource())
        await playback.load(episode: makeEpisode(title: "A", duration: 1_000))

        await playback.seek(to: 949)
        #expect(progressStore.savedProgresses.last?.isFinished == false)

        await playback.seek(to: 950)
        #expect(progressStore.savedProgresses.last?.isFinished == true)
    }

    @Test func endOfItemMarksFinishedRemovesFromQueueAndAdvances() async {
        let engine = FakePlayerEngine()
        let progressStore = FakeProgressStore()
        let queueSource = FakeQueueSource()
        let episodeA = makeEpisode(title: "A")
        let episodeB = makeEpisode(title: "B")
        queueSource.queue = [episodeB]

        let playback = Playback(engine: engine, progressStore: progressStore, queueSource: queueSource)
        await playback.load(episode: episodeA, startPlaying: true)

        await engine.simulateEndOfItem()

        #expect(queueSource.removedIDs == [episodeA.id])
        let savedForA = progressStore.savedProgresses.first { $0.episodeID == episodeA.id }
        #expect(savedForA?.isFinished == true)
        #expect(playback.currentEpisode == episodeB)
        #expect(playback.isPlaying == true)
        #expect(engine.loadedURLs.last == episodeB.audioURL)
    }

    @Test func endOfItemWithEmptyQueuePausesAndKeepsCurrentEpisode() async {
        let engine = FakePlayerEngine()
        let progressStore = FakeProgressStore()
        let queueSource = FakeQueueSource()
        let episodeA = makeEpisode(title: "A")

        let playback = Playback(engine: engine, progressStore: progressStore, queueSource: queueSource)
        await playback.load(episode: episodeA, startPlaying: true)

        await engine.simulateEndOfItem()

        #expect(queueSource.removedIDs == [episodeA.id])
        #expect(playback.currentEpisode == episodeA)
        #expect(playback.isPlaying == false)
    }

    @Test func advanceToNextEpisodeMovesOnWithoutMarkingFinished() async {
        let engine = FakePlayerEngine()
        let progressStore = FakeProgressStore()
        let queueSource = FakeQueueSource()
        let episodeA = makeEpisode(title: "A")
        let episodeB = makeEpisode(title: "B")
        queueSource.queue = [episodeB]

        let playback = Playback(engine: engine, progressStore: progressStore, queueSource: queueSource)
        await playback.load(episode: episodeA, startPlaying: true)

        await playback.advanceToNextEpisode()

        #expect(playback.currentEpisode == episodeB)
        #expect(queueSource.removedIDs.isEmpty)
        #expect(progressStore.savedProgresses.contains { $0.episodeID == episodeA.id && $0.isFinished } == false)
    }

    @Test func finishedEpisodeStartsOverWhenLoaded() async {
        let engine = FakePlayerEngine()
        let progressStore = FakeProgressStore()
        let episode = makeEpisode(title: "A")
        await progressStore.saveProgress(Progress(episodeID: episode.id, position: 1_790, duration: 1_800, isFinished: true))

        let playback = Playback(engine: engine, progressStore: progressStore, queueSource: FakeQueueSource())
        await playback.load(episode: episode)

        #expect(playback.position == 0)
    }
}
