import GRDB
import JimmyKit
import XCTest
@testable import Jimmy

/// `AppModel.apply(_:)` — the phone-side half of the watch connection (see
/// `AppModel+WatchSession.swift`): every `WatchCommand` the watch can send reaches `playback` or
/// the queue through the same methods a tap in the phone's own UI would use.
@MainActor
final class WatchCommandTests: XCTestCase {
    private func makeTempDatabasePath() -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchCommandTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("jimmy.db").path
    }

    /// Opens an `AppModel` at a fresh path, then inserts a podcast and `count` episodes directly
    /// into that same database (FK requires the episode's podcast to exist — same approach as
    /// `QueueOrderTests`), and returns `JimmyKit.Episode` values for them, matching those rows,
    /// that `AppModel.play(_:)` can load.
    private func makeModelWithEpisodes(_ count: Int) async throws -> (model: AppModel, episodes: [JimmyKit.Episode]) {
        let path = makeTempDatabasePath()
        let model = AppModel(databasePath: path)
        guard case .ready = model.launchState else {
            XCTFail("Expected AppModel to open successfully at a fresh temporary path")
            return (model, [])
        }

        let podcastID = UUID()
        // `audioURL` is set (to a local path nothing ever actually creates — no network
        // involved) so `Playback.load` resolves a URL and runs its normal "start playing" path,
        // instead of the early-return it takes for an episode with nothing playable.
        let episodes = (0..<count).map { index in
            JimmyKit.Episode(
                podcastID: podcastID,
                title: "Episode \(index)",
                audioURL: URL(fileURLWithPath: "/tmp/WatchCommandTests-nonexistent-episode-\(index).mp3")
            )
        }
        let pool = try DatabasePool(path: path)
        try await pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO podcasts (id, title, author, description, feedURL, cleanTitle)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [podcastID.uuidString, "Show", "Author", "", "https://example.com/feed.xml", "Show"]
            )
            for episode in episodes {
                try db.execute(
                    sql: """
                        INSERT INTO episodes (id, podcastID, title, played, isNew, playbackPosition, page)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [episode.id.uuidString, podcastID.uuidString, episode.title, false, true, 0.0, 1]
                )
            }
        }
        return (model, episodes)
    }

    /// `model.queue` is kept current by `store.observeQueue()` asynchronously, so assertions
    /// against it poll briefly rather than racing the observation.
    private func waitForQueue(_ model: AppModel, toEqual ids: [UUID], timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if model.queue.map(\.id) == ids { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.queue.map(\.id), ids)
    }

    // MARK: - Transport

    func testPauseCommandPausesPlayback() async throws {
        let (model, episodes) = try await makeModelWithEpisodes(1)
        await model.play(episodes[0])
        XCTAssertEqual(model.playback?.isPlaying, true)

        await model.apply(.pause)

        XCTAssertEqual(model.playback?.isPlaying, false)
    }

    func testPlayCommandResumesPlayback() async throws {
        let (model, episodes) = try await makeModelWithEpisodes(1)
        await model.play(episodes[0], startPlaying: false)
        XCTAssertEqual(model.playback?.isPlaying, false)

        await model.apply(.play)

        XCTAssertEqual(model.playback?.isPlaying, true)
    }

    func testSkipForwardCommandAdvancesPosition() async throws {
        let (model, episodes) = try await makeModelWithEpisodes(1)
        await model.play(episodes[0], startPlaying: false)
        let skipForwardInterval = try XCTUnwrap(model.playback?.skipForwardInterval)

        await model.apply(.skipForward)

        XCTAssertEqual(model.playback?.position, skipForwardInterval)
    }

    func testSkipBackwardCommandMovesPositionBack() async throws {
        let (model, episodes) = try await makeModelWithEpisodes(1)
        await model.play(episodes[0], startPlaying: false)
        await model.apply(.skipForward)
        await model.apply(.skipForward)

        await model.apply(.skipBackward)

        XCTAssertEqual(model.playback?.position, model.playback?.skipForwardInterval)
    }

    // MARK: - Queue

    func testPlayEpisodeCommandLoadsTheRequestedEpisodeAndMovesItToTheFront() async throws {
        let (model, episodes) = try await makeModelWithEpisodes(2)
        await model.enqueue(episodes[0].id, at: 1)
        await model.enqueue(episodes[1].id, at: 2)
        await waitForQueue(model, toEqual: [episodes[0].id, episodes[1].id])

        await model.apply(.playEpisode(episodes[1].id))

        XCTAssertEqual(model.playback?.currentEpisode?.id, episodes[1].id)
        await waitForQueue(model, toEqual: [episodes[1].id, episodes[0].id])
    }

    func testPlayEpisodeCommandIgnoresAnEpisodeIDTheWatchWasNeverShown() async throws {
        let (model, episodes) = try await makeModelWithEpisodes(1)
        await model.enqueue(episodes[0].id, at: 1)
        await waitForQueue(model, toEqual: [episodes[0].id])

        await model.apply(.playEpisode(UUID()))

        XCTAssertNil(model.playback?.currentEpisode)
    }

    func testRemoveFromQueueCommandDequeuesTheEpisode() async throws {
        let (model, episodes) = try await makeModelWithEpisodes(2)
        await model.enqueue(episodes[0].id, at: 1)
        await model.enqueue(episodes[1].id, at: 2)
        await waitForQueue(model, toEqual: [episodes[0].id, episodes[1].id])

        await model.apply(.removeFromQueue(episodes[0].id))

        await waitForQueue(model, toEqual: [episodes[1].id])
    }

    // MARK: - Recently played, fed into watchState()

    func testWatchStateRecentListRecordsPlayedEpisodesMostRecentFirst() async throws {
        let (model, episodes) = try await makeModelWithEpisodes(2)

        await model.play(episodes[0])
        await model.play(episodes[1])

        await waitForRecent(model, toEqual: [episodes[1].id, episodes[0].id])
    }

    /// `recordRecentlyPlayed` runs from `handlePlaybackSideEffects`, which `withObservationTracking`
    /// dispatches onto a new `Task` the moment `playback.currentEpisode` changes — not necessarily
    /// before `play()`'s own `await` returns — so this polls briefly rather than racing it.
    private func waitForRecent(_ model: AppModel, toEqual ids: [UUID], timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if model.watchState().recent.map(\.id) == ids { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.watchState().recent.map(\.id), ids)
    }
}
