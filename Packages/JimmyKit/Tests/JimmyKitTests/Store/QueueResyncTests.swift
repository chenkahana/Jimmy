import Foundation
import GRDB
import Testing
@testable import JimmyKit

/// The old app keeps writing `playback_state.queuePosition` after `v19_progress`'s one-time copy
/// into `queue` (it has no idea `queue` exists). `v23_resync_queue` re-derives `queue` from that
/// legacy column the first time a `Store` migrates past v22, so the store's queue catches up with
/// whatever the legacy app's own queue has become since.
struct QueueResyncTests {
    private func makeTempDatabasePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jimmykit-queue-resync-tests-\(UUID().uuidString).sqlite")
            .path
    }

    @Test func reopeningAfterLegacyQueueChangesResyncsTheQueue() async throws {
        let path = makeTempDatabasePath()
        let podcastID = UUID()
        let episodeIDs = [UUID(), UUID(), UUID()]

        // Build the database through the legacy (v1...v17) migrations only, then seed it with
        // data and a legacy queue of [episodeIDs[0], episodeIDs[1]], BEFORE v19 ever runs.
        var legacyMigrator = DatabaseMigrator()
        LegacyMigrations.register(on: &legacyMigrator)
        let pool = try DatabasePool(path: path)
        try legacyMigrator.migrate(pool)

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
            try db.execute(
                sql: "INSERT INTO playback_state (episodeID, position, finished, queuePosition) VALUES (?, 0, 0, 1)",
                arguments: [episodeIDs[0].uuidString]
            )
            try db.execute(
                sql: "INSERT INTO playback_state (episodeID, position, finished, queuePosition) VALUES (?, 0, 0, 2)",
                arguments: [episodeIDs[1].uuidString]
            )
        }

        // Now migrate through v22 only (not v23) — simulating a database PR 14 already opened
        // once, running v19's one-time copy against the legacy queue seeded above.
        var migrator = DatabaseMigrator()
        LegacyMigrations.register(on: &migrator)
        Migrations.register(on: &migrator, legacy: nil)
        try migrator.migrate(pool, upTo: "v22_downloads")

        // `queue` reflects v19's one-time copy, run back when this database first migrated to v22.
        let queueBeforeResync = try await pool.read { db in
            try Row.fetchAll(db, sql: "SELECT episodeID FROM queue ORDER BY position ASC").map { $0["episodeID"] as String }
        }
        #expect(queueBeforeResync == [episodeIDs[0].uuidString, episodeIDs[1].uuidString])

        // The old app kept writing `playback_state.queuePosition` since then: episodeIDs[0] is
        // dequeued, episodeIDs[2] joins the queue, and episodeIDs[1] becomes first.
        try await pool.write { db in
            try db.execute(
                sql: "UPDATE playback_state SET queuePosition = NULL WHERE episodeID = ?",
                arguments: [episodeIDs[0].uuidString]
            )
            try db.execute(
                sql: "UPDATE playback_state SET queuePosition = 1 WHERE episodeID = ?",
                arguments: [episodeIDs[1].uuidString]
            )
            try db.execute(
                sql: "INSERT INTO playback_state (episodeID, position, finished, queuePosition) VALUES (?, 0, 0, 2)",
                arguments: [episodeIDs[2].uuidString]
            )
        }
        try pool.close()

        // First real `Store` open against this file: only `v23_resync_queue` is new, and rebuilds
        // `queue` from the legacy table's CURRENT state rather than leaving it at what v19 copied
        // back when this database was still at v22.
        let store = try Store(path: path)
        #expect(try await store.queue().map(\.id) == [episodeIDs[1], episodeIDs[2]])
    }
}
