import XCTest
import GRDB
@testable import Jimmy
import JimmyKit

/// `AppModel`'s queue surface, backed by JimmyKit's `Store` (`queue` table) — the only queue now.
/// Before PR 15, this file characterized `playback_state.queuePosition`
/// (`Jimmy/Data/Repositories/GRDBRepositories.swift`, `GRDBPlaybackStateRepository`), which
/// `QueueViewModel` read from and wrote to; that repository's queue methods, `QueueViewModel` and
/// `QueueStore` are gone, so every assertion below goes through `AppModel` instead, against a real
/// `Store`. Several behaviors are an intentional CHANGE from what was characterized here before
/// (see `Packages/JimmyKit/Tests/JimmyKitTests/Store/QueueOperationsTests.swift` for the same
/// notes against `Store` directly):
/// - Dequeuing position 1 promotes the next episode, instead of leaving a gap.
/// - Enqueuing always shifts whatever's already at the target position, finished or not —
///   "finished" isn't a concept the `queue` table tracks.
/// - Enqueuing an already-queued episode moves it instead of throwing.
/// - A position past the current count clamps instead of leaving a hole.
@MainActor
final class AppModelQueueTests: XCTestCase {
    private func makeTempDatabasePath() -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModelQueueTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("jimmy.db").path
    }

    /// Opens an `AppModel` at a fresh path, then inserts a podcast and `count` episodes directly
    /// (FK requires the episode's podcast to exist; same approach as JimmyKit's own
    /// `QueueOperationsTests`), and returns their ids in insertion order.
    private func makeModelWithEpisodes(_ count: Int) async throws -> (model: AppModel, episodeIDs: [UUID]) {
        let path = makeTempDatabasePath()
        let model = AppModel(databasePath: path)
        guard case .ready = model.launchState else {
            XCTFail("Expected AppModel to open successfully at a fresh temporary path")
            return (model, [])
        }

        let podcastID = UUID()
        let episodeIDs = (0..<count).map { _ in UUID() }
        let pool = try DatabasePool(path: path)
        try await pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO podcasts (id, title, author, description, feedURL, cleanTitle)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [podcastID.uuidString, "Show", "Author", "", "https://example.com/feed.xml", "Show"]
            )
            for episodeID in episodeIDs {
                try db.execute(
                    sql: """
                        INSERT INTO episodes (id, podcastID, title, played, isNew, playbackPosition, page)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [episodeID.uuidString, podcastID.uuidString, "Episode", false, true, 0.0, 1]
                )
            }
        }
        return (model, episodeIDs)
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

    // MARK: - Enqueue

    func testEnqueueAtPosition1WhenQueueIsEmpty() async throws {
        let (model, ids) = try await makeModelWithEpisodes(1)
        await model.enqueue(ids[0], at: 1)
        await waitForQueue(model, toEqual: [ids[0]])
    }

    func testEnqueueingAtPosition1ShiftsTheExistingOccupantToPosition2() async throws {
        let (model, ids) = try await makeModelWithEpisodes(2)
        await model.enqueue(ids[0], at: 1)
        await model.enqueue(ids[1], at: 1)
        await waitForQueue(model, toEqual: [ids[1], ids[0]])
    }

    func testEnqueueingBeyondTheCurrentCountClampsInsteadOfLeavingAGap() async throws {
        let (model, ids) = try await makeModelWithEpisodes(2)
        await model.enqueue(ids[0], at: 1)
        await model.enqueue(ids[1], at: 50)
        await waitForQueue(model, toEqual: [ids[0], ids[1]])
    }

    func testEnqueueingAnAlreadyQueuedEpisodeMovesItRatherThanDuplicatingIt() async throws {
        let (model, ids) = try await makeModelWithEpisodes(2)
        await model.enqueue(ids[0], at: 1)
        await model.enqueue(ids[1], at: 2)
        await model.enqueue(ids[0], at: 2)
        await waitForQueue(model, toEqual: [ids[1], ids[0]])
    }

    func testEnqueueingWithNoPositionAppendsToTheEnd() async throws {
        let (model, ids) = try await makeModelWithEpisodes(3)
        await model.enqueue(ids[0])
        await model.enqueue(ids[1])
        await waitForQueue(model, toEqual: [ids[0], ids[1]])
        await model.enqueue(ids[2])
        await waitForQueue(model, toEqual: [ids[0], ids[1], ids[2]])
    }

    // MARK: - Dequeue

    func testDequeuingPosition1PromotesTheNextEpisode() async throws {
        let (model, ids) = try await makeModelWithEpisodes(2)
        await model.enqueue(ids[0], at: 1)
        await model.enqueue(ids[1], at: 2)

        await model.dequeue(ids[0])

        await waitForQueue(model, toEqual: [ids[1]])
    }

    func testDequeuingFromTheMiddleClosesTheGap() async throws {
        let (model, ids) = try await makeModelWithEpisodes(3)
        for (index, episodeID) in ids.enumerated() {
            await model.enqueue(episodeID, at: index + 1)
        }

        await model.dequeue(ids[1])

        await waitForQueue(model, toEqual: [ids[0], ids[2]])
    }

    func testDequeuingAnEpisodeNotInTheQueueIsANoOp() async throws {
        let (model, ids) = try await makeModelWithEpisodes(2)
        await model.enqueue(ids[0], at: 1)

        await model.dequeue(ids[1])

        await waitForQueue(model, toEqual: [ids[0]])
    }

    // MARK: - Move

    func testMoveInQueueRenumbersEverythingBetweenOldAndNewPosition() async throws {
        let (model, ids) = try await makeModelWithEpisodes(4)
        for (index, episodeID) in ids.enumerated() {
            await model.enqueue(episodeID, at: index + 1)
        }

        await model.moveInQueue(ids[2], to: 2)

        await waitForQueue(model, toEqual: [ids[0], ids[2], ids[1], ids[3]])
    }

    func testMoveToTopMovesAnAlreadyQueuedEpisodeToTheFront() async throws {
        let (model, ids) = try await makeModelWithEpisodes(3)
        for (index, episodeID) in ids.enumerated() {
            await model.enqueue(episodeID, at: index + 1)
        }

        await model.moveToTop(ids[2])

        await waitForQueue(model, toEqual: [ids[2], ids[0], ids[1]])
    }

    func testMoveToBottomMovesAnAlreadyQueuedEpisodeToTheEnd() async throws {
        let (model, ids) = try await makeModelWithEpisodes(3)
        for (index, episodeID) in ids.enumerated() {
            await model.enqueue(episodeID, at: index + 1)
        }

        await model.moveToBottom(ids[0])

        await waitForQueue(model, toEqual: [ids[1], ids[2], ids[0]])
    }

    // MARK: - Fetch ordering

    func testQueueOrdersEpisodesByPositionAscending() async throws {
        let (model, ids) = try await makeModelWithEpisodes(3)
        await model.enqueue(ids[2], at: 1)
        await model.enqueue(ids[0], at: 2)
        await model.enqueue(ids[1], at: 3)

        await waitForQueue(model, toEqual: [ids[2], ids[0], ids[1]])
    }

    func testIsQueuedReflectsCurrentMembership() async throws {
        let (model, ids) = try await makeModelWithEpisodes(2)
        XCTAssertFalse(model.isQueued(ids[0]))

        await model.enqueue(ids[0])

        await waitForQueue(model, toEqual: [ids[0]])
        XCTAssertTrue(model.isQueued(ids[0]))
        XCTAssertFalse(model.isQueued(ids[1]))
    }

    // MARK: - Whole-queue operations

    func testPlayNextInsertsAtPosition2() async throws {
        let (model, ids) = try await makeModelWithEpisodes(2)
        await model.enqueue(ids[0], at: 1)

        await model.playNext(ids[1])

        await waitForQueue(model, toEqual: [ids[0], ids[1]])
    }

    func testClearQueueRemovesEveryEpisode() async throws {
        let (model, ids) = try await makeModelWithEpisodes(3)
        for (index, episodeID) in ids.enumerated() {
            await model.enqueue(episodeID, at: index + 1)
        }

        await model.clearQueue()

        await waitForQueue(model, toEqual: [])
    }

    func testShuffleQueueKeepsEveryEpisodeQueuedExactlyOnce() async throws {
        let (model, ids) = try await makeModelWithEpisodes(5)
        for (index, episodeID) in ids.enumerated() {
            await model.enqueue(episodeID, at: index + 1)
        }

        await model.shuffleQueue()
        // Observation fires async; give it a moment, then compare as sets (order is random).
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(Set(model.queue.map(\.id)), Set(ids))
    }

    func testRemoveEpisodesFromPodcastOnlyAffectsThatPodcastsEpisodes() async throws {
        let path = makeTempDatabasePath()
        let model = AppModel(databasePath: path)
        guard case .ready = model.launchState else {
            XCTFail("Expected AppModel to open successfully at a fresh temporary path")
            return
        }

        let podcastAID = UUID()
        let podcastBID = UUID()
        let episodeA = UUID()
        let episodeB = UUID()
        let pool = try DatabasePool(path: path)
        try await pool.write { db in
            for (podcastID, title) in [(podcastAID, "Show A"), (podcastBID, "Show B")] {
                try db.execute(
                    sql: """
                        INSERT INTO podcasts (id, title, author, description, feedURL, cleanTitle)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [podcastID.uuidString, title, "Author", "", "https://example.com/\(title).xml", title]
                )
            }
            for (episodeID, podcastID) in [(episodeA, podcastAID), (episodeB, podcastBID)] {
                try db.execute(
                    sql: """
                        INSERT INTO episodes (id, podcastID, title, played, isNew, playbackPosition, page)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [episodeID.uuidString, podcastID.uuidString, "Episode", false, true, 0.0, 1]
                )
            }
        }

        await model.enqueue(episodeA, at: 1)
        await model.enqueue(episodeB, at: 2)
        await waitForQueue(model, toEqual: [episodeA, episodeB])

        await model.removeEpisodesFromPodcast(podcastBID)

        await waitForQueue(model, toEqual: [episodeA])
    }
}
