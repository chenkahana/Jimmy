import XCTest
import GRDB
#if canImport(JimmyUtilities)
@testable import JimmyUtilities
#else
@testable import Jimmy
#endif

/// Characterization tests for how queue order is stored and changed TODAY.
///
/// The actual queue ordering lives in `playback_state.queuePosition`
/// (Jimmy/Data/Repositories/GRDBRepositories.swift, GRDBPlaybackStateRepository), which is
/// what QueueViewModel reads from and writes to. `QueueStore` in
/// Jimmy/Domain/Stores/ActorStores.swift is a separate in-memory actor with its own
/// add/remove/move methods, but nothing in the app calls it — it is dead code — so these
/// tests target the repository that is actually wired up, using the isolated-DB
/// initializer added to DatabaseManager for this PR.
final class QueueOrderTests: XCTestCase {
    private func makeIsolatedRepository() async throws -> (DatabaseManager, GRDBPlaybackStateRepository) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("queue-order-tests-\(UUID().uuidString).sqlite").path
        let dbManager = try await DatabaseManager(path: path)
        return (dbManager, GRDBPlaybackStateRepository(dbManager: dbManager))
    }

    /// Inserts a podcast and `count` episodes (FK requires the episode's podcast to exist)
    /// and returns the episode IDs in insertion order.
    private func insertEpisodes(_ count: Int, dbManager: DatabaseManager) async throws -> [UUID] {
        let podcast = Podcast(title: "Show", author: "Author", feedURL: URL(string: "https://example.com/feed.xml")!)
        let episodes = (0..<count).map { Episode(title: "Episode \($0)", podcastID: podcast.id) }
        try await dbManager.writeAsync { db in
            try podcast.save(db)
            for episode in episodes { try episode.save(db) }
        }
        return episodes.map(\.id)
    }

    private func queuePosition(of episodeID: UUID, dbManager: DatabaseManager) async throws -> Int? {
        try await dbManager.readAsync { db in
            // Read via Row rather than `Int.fetchOne` so a NULL queuePosition (not queued)
            // comes back as nil instead of throwing a decoding error.
            guard let row = try Row.fetchOne(db, sql: "SELECT queuePosition FROM playback_state WHERE episodeID = ?", arguments: [episodeID.uuidString]) else {
                return nil
            }
            return row["queuePosition"] as Int?
        }
    }

    // MARK: - Add

    func testAddToQueueAtPosition1WhenQueueIsEmpty() async throws {
        let (dbManager, repo) = try await makeIsolatedRepository()
        let ids = try await insertEpisodes(1, dbManager: dbManager)

        try await repo.addToQueue(episodeID: ids[0], position: 1)

        let position = try await queuePosition(of: ids[0], dbManager: dbManager)
        XCTAssertEqual(position, 1)
    }

    func testAddingNewEpisodeAtPosition1MovesUnfinishedCurrentEpisodeToPosition2() async throws {
        // Today: adding "next" (position 1) doesn't just prepend — if something is already
        // playing (position 1) and not finished, it's pushed to the next open slot instead
        // of simply becoming position 2's occupant unconditionally.
        let (dbManager, repo) = try await makeIsolatedRepository()
        let ids = try await insertEpisodes(2, dbManager: dbManager)

        try await repo.addToQueue(episodeID: ids[0], position: 1)
        try await repo.addToQueue(episodeID: ids[1], position: 1)

        let newPosition = try await queuePosition(of: ids[1], dbManager: dbManager)
        let oldPosition = try await queuePosition(of: ids[0], dbManager: dbManager)
        XCTAssertEqual(newPosition, 1)
        XCTAssertEqual(oldPosition, 2)
    }

    func testAddingAtPosition1WhenCurrentIsFinishedRemovesItFromQueueInstead() async throws {
        let (dbManager, repo) = try await makeIsolatedRepository()
        let ids = try await insertEpisodes(2, dbManager: dbManager)

        try await repo.addToQueue(episodeID: ids[0], position: 1)
        try await repo.markFinished(episodeID: ids[0])
        try await repo.addToQueue(episodeID: ids[1], position: 1)

        let newPosition = try await queuePosition(of: ids[1], dbManager: dbManager)
        let oldPosition = try await queuePosition(of: ids[0], dbManager: dbManager)
        XCTAssertEqual(newPosition, 1)
        // Today: the finished episode is dropped from the queue (nil), not shifted to 2.
        XCTAssertNil(oldPosition)
    }

    func testInsertingInTheMiddleShiftsLaterPositionsDown() async throws {
        let (dbManager, repo) = try await makeIsolatedRepository()
        let ids = try await insertEpisodes(4, dbManager: dbManager)
        try await repo.reorderQueue(episodeIDs: [ids[0], ids[1], ids[2]]) // positions 1,2,3

        try await repo.addToQueue(episodeID: ids[3], position: 2)

        let position0 = try await queuePosition(of: ids[0], dbManager: dbManager)
        let position3 = try await queuePosition(of: ids[3], dbManager: dbManager)
        let position1 = try await queuePosition(of: ids[1], dbManager: dbManager)
        let position2 = try await queuePosition(of: ids[2], dbManager: dbManager)
        XCTAssertEqual(position0, 1)
        XCTAssertEqual(position3, 2)
        XCTAssertEqual(position1, 3)
        XCTAssertEqual(position2, 4)
    }

    func testAddingBeyondTheCurrentMaxPositionLeavesAGap() async throws {
        // Today: addToQueue does not clamp or normalize the requested position — asking
        // for a position past the current max just creates a hole in the sequence.
        let (dbManager, repo) = try await makeIsolatedRepository()
        let ids = try await insertEpisodes(2, dbManager: dbManager)
        try await repo.reorderQueue(episodeIDs: [ids[0]]) // position 1

        try await repo.addToQueue(episodeID: ids[1], position: 5)

        let position = try await queuePosition(of: ids[1], dbManager: dbManager)
        let maxPosition = try await repo.getMaxQueuePosition()
        XCTAssertEqual(position, 5)
        XCTAssertEqual(maxPosition, 5)
    }

    func testAddingAnEpisodeAlreadyInQueueThrows() async throws {
        let (dbManager, repo) = try await makeIsolatedRepository()
        let ids = try await insertEpisodes(1, dbManager: dbManager)
        try await repo.addToQueue(episodeID: ids[0], position: 1)

        await XCTAssertThrowsErrorAsync(try await repo.addToQueue(episodeID: ids[0], position: 2))
    }

    // MARK: - Move

    func testMoveInQueueRenumbersEpisodesBetweenOldAndNewPosition() async throws {
        let (dbManager, repo) = try await makeIsolatedRepository()
        let ids = try await insertEpisodes(4, dbManager: dbManager)
        try await repo.reorderQueue(episodeIDs: ids) // A=1, B=2, C=3, D=4

        try await repo.moveInQueue(episodeID: ids[2], toPosition: 2) // move C up to 2

        let positionA = try await queuePosition(of: ids[0], dbManager: dbManager)
        let positionC = try await queuePosition(of: ids[2], dbManager: dbManager)
        let positionB = try await queuePosition(of: ids[1], dbManager: dbManager)
        let positionD = try await queuePosition(of: ids[3], dbManager: dbManager)
        XCTAssertEqual(positionA, 1) // A unchanged
        XCTAssertEqual(positionC, 2) // C moved here
        XCTAssertEqual(positionB, 3) // B shifted down
        XCTAssertEqual(positionD, 4) // D unchanged
    }

    func testCannotMoveADifferentEpisodeToPosition1() async throws {
        // Position 1 is reserved for whatever is "currently playing"; moveInQueue refuses
        // to hand it to another episode directly.
        let (dbManager, repo) = try await makeIsolatedRepository()
        let ids = try await insertEpisodes(2, dbManager: dbManager)
        try await repo.reorderQueue(episodeIDs: ids)

        await XCTAssertThrowsErrorAsync(try await repo.moveInQueue(episodeID: ids[1], toPosition: 1))
    }

    func testMovingAnEpisodeToItsOwnPositionIsANoOp() async throws {
        let (dbManager, repo) = try await makeIsolatedRepository()
        let ids = try await insertEpisodes(1, dbManager: dbManager)
        try await repo.reorderQueue(episodeIDs: ids) // position 1

        try await repo.moveInQueue(episodeID: ids[0], toPosition: 1)

        let position = try await queuePosition(of: ids[0], dbManager: dbManager)
        XCTAssertEqual(position, 1)
    }

    // MARK: - Remove

    func testRemovingFromTheMiddleShiftsLaterPositionsDown() async throws {
        let (dbManager, repo) = try await makeIsolatedRepository()
        let ids = try await insertEpisodes(3, dbManager: dbManager)
        try await repo.reorderQueue(episodeIDs: ids) // A=1, B=2, C=3

        try await repo.removeFromQueue(episodeID: ids[1]) // remove B

        let positionA = try await queuePosition(of: ids[0], dbManager: dbManager)
        let positionB = try await queuePosition(of: ids[1], dbManager: dbManager)
        let positionC = try await queuePosition(of: ids[2], dbManager: dbManager)
        XCTAssertEqual(positionA, 1)
        XCTAssertNil(positionB)
        XCTAssertEqual(positionC, 2)
    }

    func testRemovingTheCurrentlyPlayingEpisodeLeavesAGapInsteadOfPromotingTheNext() async throws {
        // Today: removing position 1 just marks it finished and clears its queuePosition —
        // it explicitly skips the renumbering shift, so nothing is promoted into slot 1.
        let (dbManager, repo) = try await makeIsolatedRepository()
        let ids = try await insertEpisodes(2, dbManager: dbManager)
        try await repo.reorderQueue(episodeIDs: ids) // A=1, B=2

        try await repo.removeFromQueue(episodeID: ids[0])

        let positionA = try await queuePosition(of: ids[0], dbManager: dbManager)
        let positionB = try await queuePosition(of: ids[1], dbManager: dbManager)
        XCTAssertNil(positionA)
        XCTAssertEqual(positionB, 2) // still 2, not promoted to 1

        let queued = try await repo.fetchQueuedEpisodes()
        XCTAssertEqual(queued.count, 1)
    }

    // MARK: - Reorder

    func testReorderQueueDropsEpisodesNotInTheNewList() async throws {
        // Today: reorderQueue clears every existing queuePosition first, then only the
        // IDs passed in get a fresh position — anything left out silently falls out of
        // the queue rather than keeping its old slot.
        let (dbManager, repo) = try await makeIsolatedRepository()
        let ids = try await insertEpisodes(3, dbManager: dbManager)
        try await repo.reorderQueue(episodeIDs: ids)

        try await repo.reorderQueue(episodeIDs: [ids[2], ids[0]])

        let positionC = try await queuePosition(of: ids[2], dbManager: dbManager)
        let positionA = try await queuePosition(of: ids[0], dbManager: dbManager)
        let positionB = try await queuePosition(of: ids[1], dbManager: dbManager)
        XCTAssertEqual(positionC, 1)
        XCTAssertEqual(positionA, 2)
        XCTAssertNil(positionB)
    }

    func testReorderQueueCanAssignPosition1EvenThoughMoveInQueueWouldRefuseTo() async throws {
        // Today: unlike moveInQueue, reorderQueue has no special-casing for position 1 —
        // it freely assigns it to whichever episode is first in the given list.
        let (dbManager, repo) = try await makeIsolatedRepository()
        let ids = try await insertEpisodes(2, dbManager: dbManager)
        try await repo.addToQueue(episodeID: ids[0], position: 1)

        try await repo.reorderQueue(episodeIDs: [ids[1], ids[0]])

        let positionB = try await queuePosition(of: ids[1], dbManager: dbManager)
        let positionA = try await queuePosition(of: ids[0], dbManager: dbManager)
        XCTAssertEqual(positionB, 1)
        XCTAssertEqual(positionA, 2)
    }

    // MARK: - Fetch

    func testFetchQueuedEpisodesOrdersByQueuePositionAscending() async throws {
        let (dbManager, repo) = try await makeIsolatedRepository()
        let ids = try await insertEpisodes(3, dbManager: dbManager)
        try await repo.reorderQueue(episodeIDs: [ids[2], ids[0], ids[1]])

        let queued = try await repo.fetchQueuedEpisodes()

        XCTAssertEqual(queued.map(\.episode.id), [ids[2], ids[0], ids[1]])
    }

    func testGetNextQueuedEpisodeReturnsPosition1() async throws {
        let (dbManager, repo) = try await makeIsolatedRepository()
        let ids = try await insertEpisodes(2, dbManager: dbManager)
        try await repo.reorderQueue(episodeIDs: ids)

        let next = try await repo.getNextQueuedEpisode()

        XCTAssertEqual(next?.episode.id, ids[0])
    }
}

/// Small async-friendly wrapper, since XCTAssertThrowsError doesn't accept `async throws` expressions directly.
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error to be thrown", file: file, line: line)
    } catch {
        // expected
    }
}
