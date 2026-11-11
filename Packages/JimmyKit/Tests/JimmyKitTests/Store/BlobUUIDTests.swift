import Foundation
import GRDB
import Testing
@testable import JimmyKit

/// Older builds wrote some UUID columns as 16-byte blobs; today's app reads both forms.
/// The store must keep those rows' identity (no new random ids) and link them across tables.
struct BlobUUIDTests {
    private func blob(_ uuid: UUID) -> Data {
        withUnsafeBytes(of: uuid.uuid) { Data($0) }
    }

    private func makeLegacyDatabase() throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("jimmykit-blob-\(UUID().uuidString).sqlite").path
        var migrator = DatabaseMigrator()
        LegacyMigrations.register(on: &migrator)
        let pool = try DatabasePool(path: path)
        try migrator.migrate(pool)
        try pool.close()
        return path
    }

    @Test func blobIDsKeepTheirIdentityAndLinkAcrossTables() async throws {
        let path = try makeLegacyDatabase()
        let podcastID = UUID()
        let episodeID = UUID()

        let podcastBlob = blob(podcastID)
        let episodeBlob = blob(episodeID)
        let pool = try DatabasePool(path: path)
        try await pool.write { db in
            try db.execute(
                sql: "INSERT INTO podcasts (id, title, author, description, feedURL, cleanTitle) VALUES (?, 'Show', 'A', '', 'https://example.com/f.xml', 'Show')",
                arguments: [podcastBlob]
            )
            try db.execute(
                sql: "INSERT INTO episodes (id, podcastID, title, duration, played, isNew, playbackPosition, status, starred) VALUES (?, ?, 'Ep', 1800, 0, 0, 0, 0, 0)",
                arguments: [episodeBlob, podcastBlob]
            )
            try db.execute(
                sql: "INSERT INTO playback_state (episodeID, position, finished, queuePosition, updatedAt) VALUES (?, 120, 0, 1, ?)",
                arguments: [episodeBlob, Date()]
            )
        }
        try pool.close()

        let store = try Store(path: path)

        #expect(try await store.podcasts().map(\.id) == [podcastID])
        #expect(try await store.episodes(podcastID: podcastID).map(\.id) == [episodeID])
        #expect(try await store.progress(for: episodeID)?.position == 120)
        #expect(try await store.queue().map(\.id) == [episodeID])
    }

    @Test func corruptLegacySourceIsSkippedAndKeptVerbatim() async throws {
        let path = try makeLegacyDatabase()
        let corrupt = Data("not json".utf8)

        let store = try Store(path: path, legacy: LegacyInput(savedPodcastsData: corrupt, listeningStatsData: corrupt))

        #expect(try await store.podcasts().isEmpty)
        let pool = try DatabasePool(path: path)
        let kept = try await pool.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'legacy.saved_podcasts'")
        }
        #expect(kept == corrupt.base64EncodedString())
    }
}
