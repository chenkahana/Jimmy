import Foundation
import GRDB
import Testing
@testable import JimmyKit

/// The old app kept writing `episodes.playbackPosition`/`played`/`status` and
/// `playback_state.position`/`finished` after `v19_progress`'s one-time copy into `progress`.
/// `v24_resync_progress` re-derives `progress` from those legacy columns the first time a
/// `Store` migrates past v23, so the store's progress catches up with whatever the legacy app's
/// own playback state has become since.
struct ProgressResyncTests {
    private func makeTempDatabasePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jimmykit-progress-resync-tests-\(UUID().uuidString).sqlite")
            .path
    }

    @Test func reopeningAfterLegacyProgressChangesResyncsProgress() async throws {
        let path = makeTempDatabasePath()
        let podcastID = UUID()
        let episodeID = UUID()

        // Build the database through the legacy (v1...v17) migrations only, then seed it with
        // data and a legacy progress of position 10, BEFORE v19 ever runs.
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
            try db.execute(
                sql: """
                    INSERT INTO episodes (id, podcastID, title, played, isNew, playbackPosition, page)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [episodeID.uuidString, podcastID.uuidString, "Episode", false, true, 10.0, 1]
            )
            try db.execute(
                sql: "INSERT INTO playback_state (episodeID, position, finished, queuePosition) VALUES (?, 10, 0, NULL)",
                arguments: [episodeID.uuidString]
            )
        }

        // Migrate through v23 only (not v24) — simulating a database that already migrated once,
        // running v19's one-time copy against the legacy progress seeded above.
        var migrator = DatabaseMigrator()
        LegacyMigrations.register(on: &migrator)
        Migrations.register(on: &migrator, legacy: nil)
        try migrator.migrate(pool, upTo: "v23_resync_queue")

        let progressBeforeResync: (position: Double, isFinished: Bool)? = try await pool.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT position, isFinished FROM progress WHERE episodeID = ?", arguments: [episodeID.uuidString]
            ) else { return nil }
            return (row["position"] as Double, row["isFinished"] as Bool)
        }
        #expect(progressBeforeResync?.position == 10.0)
        #expect(progressBeforeResync?.isFinished == false)

        // The old app kept writing the legacy columns since then: the episode finished at 123s.
        try await pool.write { db in
            try db.execute(
                sql: "UPDATE episodes SET playbackPosition = 123, played = 1 WHERE id = ?",
                arguments: [episodeID.uuidString]
            )
            try db.execute(
                sql: "UPDATE playback_state SET position = 123, finished = 1 WHERE episodeID = ?",
                arguments: [episodeID.uuidString]
            )
        }
        try pool.close()

        // First real `Store` open against this file: only `v24_resync_progress` is new, and
        // rebuilds `progress` from the legacy columns' CURRENT state rather than leaving it at
        // what v19 copied back when this database was still at v23.
        let store = try Store(path: path)
        let progress = try await store.progress(for: episodeID)
        #expect(progress?.position == 123)
        #expect(progress?.isFinished == true)
    }
}
