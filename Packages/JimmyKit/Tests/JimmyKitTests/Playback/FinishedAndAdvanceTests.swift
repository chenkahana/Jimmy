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
        // Exactly one save for A: `load(episodeB)`'s own initial `flush()` must not re-persist (and
        // un-finish) episode A behind the finish save above, which is what made this a `.last`
        // check instead of `.first` — a regression `load(next)`'s flush used to cause whenever
        // `position` hadn't caught up to `duration` yet (e.g. right here, where it's still 0).
        let savesForA = progressStore.savedProgresses.filter { $0.episodeID == episodeA.id }
        #expect(savesForA.count == 1)
        #expect(savesForA.last?.isFinished == true)
        #expect(savesForA.last?.position == 0)
        #expect(playback.currentEpisode == episodeB)
        #expect(playback.isPlaying == true)
        #expect(engine.loadedURLs.last == episodeB.audioURL)
    }

    /// F1: auto-advance must resolve the next episode's URL the same way a direct `load` does —
    /// not just the episode `AppModel.play` was called with directly.
    @Test func autoAdvanceOnFinishResolvesTheNextEpisodesURLToo() async {
        let engine = FakePlayerEngine()
        let progressStore = FakeProgressStore()
        let queueSource = FakeQueueSource()
        let episodeA = makeEpisode(title: "A")
        let episodeB = makeEpisode(title: "B")
        queueSource.queue = [episodeB]
        let downloadedURLForB = URL(fileURLWithPath: "/tmp/B-downloaded.mp3")

        let playback = Playback(engine: engine, progressStore: progressStore, queueSource: queueSource)
        playback.resolveAudioURL = { $0.id == episodeB.id ? downloadedURLForB : $0.audioURL }
        await playback.load(episode: episodeA, startPlaying: true)

        await engine.simulateEndOfItem()

        #expect(engine.loadedURLs.last == downloadedURLForB)
    }

    /// F5: a finished episode's id is reported even when there's no next episode to advance to, so
    /// `AppModel` can clear `lastPlayingEpisodeID` right away instead of it still pointing at an
    /// episode that's already done.
    @Test func onEpisodeFinishedFiresForTheFinishedEpisodeEvenWithoutANextEpisode() async {
        let engine = FakePlayerEngine()
        let progressStore = FakeProgressStore()
        let episodeA = makeEpisode(title: "A")

        let playback = Playback(engine: engine, progressStore: progressStore, queueSource: FakeQueueSource())
        var finishedIDs: [UUID] = []
        playback.onEpisodeFinished = { finishedIDs.append($0) }
        await playback.load(episode: episodeA, startPlaying: true)

        await engine.simulateEndOfItem()

        #expect(finishedIDs == [episodeA.id])
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

    /// F1: the remote "next track" command's `advanceToNextEpisode` must also resolve the next
    /// episode's URL, exactly like a direct `load` — it's the same resolver, not a special case.
    @Test func advanceToNextEpisodeResolvesItsURLToo() async {
        let engine = FakePlayerEngine()
        let progressStore = FakeProgressStore()
        let queueSource = FakeQueueSource()
        let episodeA = makeEpisode(title: "A")
        let episodeB = makeEpisode(title: "B")
        queueSource.queue = [episodeB]
        let downloadedURLForB = URL(fileURLWithPath: "/tmp/B-downloaded.mp3")

        let playback = Playback(engine: engine, progressStore: progressStore, queueSource: queueSource)
        playback.resolveAudioURL = { $0.id == episodeB.id ? downloadedURLForB : $0.audioURL }
        await playback.load(episode: episodeA, startPlaying: true)

        await playback.advanceToNextEpisode()

        #expect(engine.loadedURLs.last == downloadedURLForB)
    }

    /// F2: an episode the legacy "played" flag was set on (what `v24_resync_progress` backfills
    /// into `isFinished`) still has its real last-known position saved alongside it — unlike a
    /// true finish, which always zeroes `position` (see the test below). Resuming it must pick up
    /// where it left off, not restart at 0:00.
    @Test func legacyPlayedEpisodeResumesAtItsSavedPositionInsteadOfRestarting() async {
        let engine = FakePlayerEngine()
        let progressStore = FakeProgressStore()
        let episode = makeEpisode(title: "A")
        await progressStore.saveProgress(Progress(episodeID: episode.id, position: 1_790, duration: 1_800, isFinished: true))

        let playback = Playback(engine: engine, progressStore: progressStore, queueSource: FakeQueueSource())
        await playback.load(episode: episode)

        #expect(playback.position == 1_790)
    }

    /// F2: only an episode that actually just finished starts over — because `finishCurrentEpisode`
    /// is what zeroes its saved position, not `load` reacting to `isFinished`.
    @Test func aGenuinelyFinishedEpisodeRestartsAtZeroWhenLoadedAgain() async {
        let engine = FakePlayerEngine()
        let progressStore = FakeProgressStore()
        let episode = makeEpisode(title: "A")
        let playback = Playback(engine: engine, progressStore: progressStore, queueSource: FakeQueueSource())
        await playback.load(episode: episode, startPlaying: true)
        await engine.simulateEndOfItem()

        await playback.load(episode: episode)

        #expect(playback.position == 0)
    }
}
