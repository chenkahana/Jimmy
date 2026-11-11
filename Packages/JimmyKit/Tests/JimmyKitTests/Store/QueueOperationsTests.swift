import Foundation
import GRDB
import Testing
@testable import JimmyKit

/// `Store`'s queue always keeps positions `1...n`, with no gaps and no duplicates — enforced by
/// `enqueue`/`dequeue`/`moveInQueue` themselves, not left to callers. Dequeuing position 1
/// promotes the next episode into position 1; this is an intentional behavior CHANGE from
/// today's app, where `GRDBPlaybackStateRepository.removeFromQueue` leaves position 1 empty
/// instead of promoting (see `Tests/JimmyTests/QueueOrderTests.swift`).
struct QueueOperationsTests {
    private func makeTempDatabasePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jimmykit-queue-tests-\(UUID().uuidString).sqlite")
            .path
    }

    private func makeStoreWithEpisodes(count: Int) async throws -> (store: Store, path: String, episodeIDs: [UUID]) {
        let path = makeTempDatabasePath()
        var migrator = DatabaseMigrator()
        LegacyMigrations.register(on: &migrator)
        let pool = try DatabasePool(path: path)
        try migrator.migrate(pool)

        let podcastID = UUID()
        let episodeIDs = (0..<count).map { _ in UUID() }
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
        try pool.close()

        let store = try Store(path: path)
        return (store, path, episodeIDs)
    }

    /// The raw `queue.position` values, ordered ascending — used to assert the 1...n,
    /// no-gaps, no-duplicates invariant directly against the table, not just via `queue()`'s
    /// episode ordering.
    private func rawQueuePositions(path: String) async throws -> [Int] {
        let pool = try DatabasePool(path: path)
        defer { try? pool.close() }
        return try await pool.read { db in
            try Int.fetchAll(db, sql: "SELECT position FROM queue ORDER BY position ASC")
        }
    }

    // MARK: - Enqueue

    @Test func enqueueAtPosition1WhenQueueIsEmpty() async throws {
        let (store, path, ids) = try await makeStoreWithEpisodes(count: 1)
        try await store.enqueue(ids[0], at: 1)

        #expect(try await store.queue().map(\.id) == [ids[0]])
        #expect(try await rawQueuePositions(path: path) == [1])
    }

    @Test func enqueueingAtPosition1ShiftsTheExistingOccupantToPosition2() async throws {
        let (store, path, ids) = try await makeStoreWithEpisodes(count: 2)
        try await store.enqueue(ids[0], at: 1)
        try await store.enqueue(ids[1], at: 1)

        #expect(try await store.queue().map(\.id) == [ids[1], ids[0]])
        #expect(try await rawQueuePositions(path: path) == [1, 2])
    }

    @Test func enqueueingBeyondTheCurrentCountClampsInsteadOfLeavingAGap() async throws {
        let (store, path, ids) = try await makeStoreWithEpisodes(count: 2)
        try await store.enqueue(ids[0], at: 1)
        try await store.enqueue(ids[1], at: 50)

        #expect(try await store.queue().map(\.id) == [ids[0], ids[1]])
        #expect(try await rawQueuePositions(path: path) == [1, 2])
    }

    @Test func enqueueingAnAlreadyQueuedEpisodeMovesItRatherThanDuplicatingIt() async throws {
        let (store, path, ids) = try await makeStoreWithEpisodes(count: 2)
        try await store.enqueue(ids[0], at: 1)
        try await store.enqueue(ids[1], at: 2)

        try await store.enqueue(ids[0], at: 2)

        #expect(try await store.queue().map(\.id) == [ids[1], ids[0]])
        #expect(try await rawQueuePositions(path: path) == [1, 2])
    }

    // MARK: - Dequeue

    @Test func dequeuingPosition1PromotesTheNextEpisode() async throws {
        let (store, path, ids) = try await makeStoreWithEpisodes(count: 2)
        try await store.enqueue(ids[0], at: 1)
        try await store.enqueue(ids[1], at: 2)

        try await store.dequeue(ids[0])

        #expect(try await store.queue().map(\.id) == [ids[1]])
        #expect(try await rawQueuePositions(path: path) == [1])
    }

    @Test func dequeuingFromTheMiddleClosesTheGap() async throws {
        let (store, path, ids) = try await makeStoreWithEpisodes(count: 3)
        for (index, episodeID) in ids.enumerated() {
            try await store.enqueue(episodeID, at: index + 1)
        }

        try await store.dequeue(ids[1])

        #expect(try await store.queue().map(\.id) == [ids[0], ids[2]])
        #expect(try await rawQueuePositions(path: path) == [1, 2])
    }

    @Test func dequeuingAnEpisodeNotInTheQueueIsANoOp() async throws {
        let (store, _, ids) = try await makeStoreWithEpisodes(count: 2)
        try await store.enqueue(ids[0], at: 1)

        try await store.dequeue(ids[1])

        #expect(try await store.queue().map(\.id) == [ids[0]])
    }

    // MARK: - Move

    @Test func moveInQueueRenumbersEverythingBetweenOldAndNewPosition() async throws {
        let (store, path, ids) = try await makeStoreWithEpisodes(count: 4)
        for (index, episodeID) in ids.enumerated() {
            try await store.enqueue(episodeID, at: index + 1)
        }

        try await store.moveInQueue(ids[2], to: 2)

        #expect(try await store.queue().map(\.id) == [ids[0], ids[2], ids[1], ids[3]])
        #expect(try await rawQueuePositions(path: path) == [1, 2, 3, 4])
    }

    @Test func movingAnEpisodeToItsOwnPositionIsANoOp() async throws {
        let (store, path, ids) = try await makeStoreWithEpisodes(count: 1)
        try await store.enqueue(ids[0], at: 1)

        try await store.moveInQueue(ids[0], to: 1)

        #expect(try await store.queue().map(\.id) == [ids[0]])
        #expect(try await rawQueuePositions(path: path) == [1])
    }

    // MARK: - Fetch ordering

    @Test func queueOrdersEpisodesByPositionAscending() async throws {
        let (store, _, ids) = try await makeStoreWithEpisodes(count: 3)
        try await store.enqueue(ids[2], at: 1)
        try await store.enqueue(ids[0], at: 2)
        try await store.enqueue(ids[1], at: 3)

        #expect(try await store.queue().map(\.id) == [ids[2], ids[0], ids[1]])
    }
}
