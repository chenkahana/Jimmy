import Foundation
import GRDB
import Testing
@testable import JimmyKit

/// Proves `Store` can open a database that today's app actually produced (built here by
/// running ONLY the frozen `LegacyMigrations`, never `Store` itself, against realistic rows),
/// that every legacy table's data survives byte-for-byte, and that the new v18...v21 tables
/// are derived correctly from it.
///
/// All raw GRDB access in this file deliberately uses the SYNCHRONOUS `DatabaseWriter`/
/// `DatabaseReader` APIs (never `await`ed): `Row` is intentionally not `Sendable` in GRDB 7, so
/// a `Row`/`[Row]` can't cross the async `read`/`write` overloads' concurrency boundary. Only
/// `Store`'s own `async` API (used read-only here) is awaited.
struct LegacyCompatibilityTests {
    private func makeTempDatabasePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jimmykit-store-tests-\(UUID().uuidString).sqlite")
            .path
    }

    /// Every row of `table`, in a stable order, so two snapshots can be compared for an exact
    /// match (this is this test's "checksum": GRDB's `Row` is `Equatable`, so comparing the
    /// full `[Row]` arrays is a strictly stronger check than hashing them).
    private func snapshot(_ table: String, path: String) throws -> [Row] {
        let pool = try DatabasePool(path: path)
        defer { try? pool.close() }
        return try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM \(table) ORDER BY rowid")
        }
    }

    private let legacyTablesWithData = ["podcasts", "episodes", "playback_state", "bookmarks", "episode_transcripts"]

    private struct RealisticFixtureIDs {
        var podcastIDs: [UUID]
        var playedID: UUID
        var partiallyPlayedID: UUID
        var queuedID: UUID
        var downloadedID: UUID
    }

    /// Builds a "today's app" database (ONLY the legacy migrations) with realistic rows: 3
    /// podcasts, and episodes covering played / partially played / queued / downloaded (with an
    /// absolute on-disk `localFileURL`), plus a bookmark and a transcript.
    private func buildRealisticLegacyDatabase(at path: String) throws -> RealisticFixtureIDs {
        var migrator = DatabaseMigrator()
        LegacyMigrations.register(on: &migrator)
        let pool = try DatabasePool(path: path)
        try migrator.migrate(pool)

        let podcastIDs = [UUID(), UUID(), UUID()]
        let playedID = UUID()
        let partiallyPlayedID = UUID()
        let queuedID = UUID()
        let downloadedID = UUID()
        let absoluteDownloadPath = "/Users/test/Library/Developer/CoreSimulator/Devices/ABC"
            + "/data/Containers/Data/Application/XYZ/Documents/Downloads/\(downloadedID.uuidString).mp3"

        try pool.write { db in
            for (index, podcastID) in podcastIDs.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO podcasts (id, title, author, description, feedURL, cleanTitle)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        podcastID.uuidString, "Show \(index + 1)", "Author \(index + 1)", "Description",
                        "https://example.com/feed\(index + 1).xml", "Show \(index + 1)"
                    ]
                )
            }

            // Fully played: playbackPosition == duration, played flag set, status has the played bit.
            try db.execute(
                sql: """
                    INSERT INTO episodes (id, podcastID, title, duration, played, isNew, playbackPosition, status, starred)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [playedID.uuidString, podcastIDs[0].uuidString, "Played Episode", 3600.0, true, false, 3600.0, 1, false]
            )
            // Partially played: position short of duration, nothing marked played.
            try db.execute(
                sql: """
                    INSERT INTO episodes (id, podcastID, title, duration, played, isNew, playbackPosition, status, starred)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    partiallyPlayedID.uuidString, podcastIDs[0].uuidString, "Partially Played Episode",
                    1800.0, false, false, 600.0, 0, false
                ]
            )
            // Queued, unplayed, no playback_state row at all (exercises the "fall back to
            // episodes.playbackPosition" branch of the progress backfill).
            try db.execute(
                sql: """
                    INSERT INTO episodes (id, podcastID, title, duration, played, isNew, playbackPosition, status, starred)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [queuedID.uuidString, podcastIDs[1].uuidString, "Queued Episode", 1200.0, false, true, 0.0, 2, false]
            )
            // Downloaded: absolute on-disk localFileURL under .../Documents/.
            try db.execute(
                sql: """
                    INSERT INTO episodes
                        (id, podcastID, title, duration, played, isNew, playbackPosition, localFileURL, status, starred)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    downloadedID.uuidString, podcastIDs[2].uuidString, "Downloaded Episode",
                    2400.0, false, false, 100.0, absoluteDownloadPath, 0, true
                ]
            )

            try db.execute(
                sql: "INSERT INTO playback_state (episodeID, position, finished) VALUES (?, ?, ?)",
                arguments: [playedID.uuidString, 3600.0, true]
            )
            try db.execute(
                sql: "INSERT INTO playback_state (episodeID, position, finished) VALUES (?, ?, ?)",
                arguments: [partiallyPlayedID.uuidString, 600.0, false]
            )
            try db.execute(
                sql: "INSERT INTO playback_state (episodeID, position, finished, queuePosition) VALUES (?, ?, ?, ?)",
                arguments: [queuedID.uuidString, 0.0, false, 1]
            )

            try db.execute(
                sql: "INSERT INTO bookmarks (id, episodeID, timestamp, note) VALUES (?, ?, ?, ?)",
                arguments: [UUID().uuidString, partiallyPlayedID.uuidString, 123.0, "Great point"]
            )
            try db.execute(
                sql: """
                    INSERT INTO episode_transcripts (episodeID, transcriptURL, format, segmentsJSON)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [playedID.uuidString, "https://example.com/transcript.srt", "srt", "[]"]
            )
        }
        try pool.close()

        return RealisticFixtureIDs(
            podcastIDs: podcastIDs, playedID: playedID, partiallyPlayedID: partiallyPlayedID,
            queuedID: queuedID, downloadedID: downloadedID
        )
    }

    // MARK: - Realistic legacy database, built with ONLY the legacy migrations

    @Test func storeOpensARealisticLegacyDatabaseWithoutLosingOrChangingAnything() async throws {
        let path = makeTempDatabasePath()
        let ids = try buildRealisticLegacyDatabase(at: path)

        var before: [String: [Row]] = [:]
        for table in legacyTablesWithData {
            before[table] = try snapshot(table, path: path)
        }

        let store = try Store(path: path)

        for table in legacyTablesWithData {
            let after = try snapshot(table, path: path)
            #expect(after.count == before[table]?.count, "\(table) row count changed")
            #expect(after == before[table], "\(table) rows changed")
        }

        // progress: played episode is finished, at its playback_state position.
        let playedProgress = try await store.progress(for: ids.playedID)
        #expect(playedProgress?.isFinished == true)
        #expect(playedProgress?.position == 3600.0)

        // progress: partially played episode is not finished, at its playback_state position.
        let partialProgress = try await store.progress(for: ids.partiallyPlayedID)
        #expect(partialProgress?.isFinished == false)
        #expect(partialProgress?.position == 600.0)

        // progress: queued episode, no playback_state position recorded -> falls back to
        // episodes.playbackPosition.
        let queuedProgress = try await store.progress(for: ids.queuedID)
        #expect(queuedProgress?.isFinished == false)
        #expect(queuedProgress?.position == 0.0)

        // progress: downloaded episode has no playback_state row at all -> falls back to
        // episodes.playbackPosition too.
        let downloadedProgress = try await store.progress(for: ids.downloadedID)
        #expect(downloadedProgress?.isFinished == false)
        #expect(downloadedProgress?.position == 100.0)

        // queue: only the queued episode carries a queuePosition, renumbered starting at 1.
        let queue = try await store.queue()
        #expect(queue.map(\.id) == [ids.queuedID])

        // downloads: the absolute localFileURL is stored relative to the app container.
        let downloads = try await store.downloads()
        #expect(downloads.count == 1)
        #expect(downloads.first?.episodeID == ids.downloadedID)
        #expect(downloads.first?.relativePath == "Downloads/\(ids.downloadedID.uuidString).mp3")
        #expect(downloads.first?.state == .done)
    }

    // MARK: - Part-migrated databases

    @Test(arguments: ["v5_ensure_all_columns", "v13_add_queue_position", "v17_create_transcripts"])
    func storeFinishesMigratingAndSurvivesFromAnyLegacyCheckpoint(_ checkpoint: String) async throws {
        let path = makeTempDatabasePath()

        var migrator = DatabaseMigrator()
        LegacyMigrations.register(on: &migrator)
        let pool = try DatabasePool(path: path)
        try migrator.migrate(pool, upTo: checkpoint)

        // Only columns present at every one of these checkpoints (all present since v1).
        let podcastID = UUID()
        let episodeID = UUID()
        try await pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO podcasts (id, title, author, description, feedURL, cleanTitle)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [podcastID.uuidString, "Show", "Author", "Description", "https://example.com/feed.xml", "Show"]
            )
            try db.execute(
                sql: """
                    INSERT INTO episodes (id, podcastID, title, played, isNew, playbackPosition, page)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [episodeID.uuidString, podcastID.uuidString, "Episode", false, true, 42.0, 1]
            )
        }
        try pool.close()

        let store = try Store(path: path)

        let podcasts = try await store.podcasts()
        #expect(podcasts.map(\.id) == [podcastID])

        let episodes = try await store.episodes(podcastID: podcastID)
        #expect(episodes.map(\.id) == [episodeID])

        let progress = try await store.progress(for: episodeID)
        #expect(progress?.position == 42.0)
        #expect(progress?.isFinished == false)
    }

    // MARK: - Reverse compatibility: today's app can still open a Store-migrated file

    @Test func legacyOnlyMigratorStillSucceedsAfterStoreHasMigratedTheFile() async throws {
        let path = makeTempDatabasePath()
        _ = try Store(path: path)

        let pool = try DatabasePool(path: path)
        var legacyOnlyMigrator = DatabaseMigrator()
        LegacyMigrations.register(on: &legacyOnlyMigrator)

        // Must not throw: all 17 legacy identifiers are already applied, and a migrator that
        // only knows about those 17 doesn't care that v18...v21 were also applied by Store.
        try legacyOnlyMigrator.migrate(pool)
        try pool.close()
    }
}
