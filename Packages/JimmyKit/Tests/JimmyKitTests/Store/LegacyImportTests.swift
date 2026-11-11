import Foundation
import GRDB
import Testing
@testable import JimmyKit

/// Exercises `v20_legacy_import` against the real fixtures in `Tests/Fixtures/LegacyData`
/// (read via a `#filePath`-relative URL, same approach as `LegacyDataDecodingTests`, so no
/// `Package.swift` resources are needed), and proves the import runs exactly once.
struct LegacyImportTests {
    /// `Tests/Fixtures/LegacyData`, resolved relative to this source file.
    private var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Store
            .deletingLastPathComponent() // JimmyKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // JimmyKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Tests/Fixtures/LegacyData")
    }

    private func load(_ filename: String) throws -> Data {
        try Data(contentsOf: fixturesDirectory.appendingPathComponent(filename))
    }

    private func makeTempDatabasePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jimmykit-import-tests-\(UUID().uuidString).sqlite")
            .path
    }

    /// `episode_queue.json`'s first and third episode ids (order: 1, 2, 3, 4). Episode 2 and 4
    /// are deliberately left out of the `episodes` table, to prove queue import both preserves
    /// file order and skips episodes that don't exist.
    private let queuedEpisode1 = UUID(uuidString: "660e8400-e29b-41d4-a716-446655550001")!
    private let queuedEpisode3 = UUID(uuidString: "660e8400-e29b-41d4-a716-446655550003")!

    /// Builds a legacy (v1...v17 only) database with just enough pre-existing data for the
    /// queue import to have something to match against, and returns its path.
    private func makeSeededLegacyDatabase() async throws -> String {
        let path = makeTempDatabasePath()
        var migrator = DatabaseMigrator()
        LegacyMigrations.register(on: &migrator)
        let pool = try DatabasePool(path: path)
        try migrator.migrate(pool)

        let podcastID = UUID()
        try await pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO podcasts (id, title, author, description, feedURL, cleanTitle)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [podcastID.uuidString, "Pre-existing Show", "Author", "Desc", "https://example.com/pre.xml", "Pre-existing Show"]
            )
            for episodeID in [queuedEpisode1, queuedEpisode3] {
                try db.execute(
                    sql: """
                        INSERT INTO episodes (id, podcastID, title, played, isNew, playbackPosition, page)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [episodeID.uuidString, podcastID.uuidString, "Pre-existing Episode", false, true, 0.0, 1]
                )
            }
        }
        try pool.close()
        return path
    }

    private func legacyInput() throws -> LegacyInput {
        LegacyInput(
            savedPodcastsData: try load("saved_podcasts.json"),
            appDataPodcastsData: try load("podcasts.json"),
            episodeQueueData: try load("episode_queue.json"),
            listeningStatsData: try load("listening_stats.json"),
            lastPlayedEpisodeID: queuedEpisode1
        )
    }

    private func settingValue(for key: String, path: String) async throws -> String? {
        let pool = try DatabasePool(path: path)
        defer { try? pool.close() }
        return try await pool.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
        }
    }

    private func listeningStatsRowCount(path: String) async throws -> Int {
        let pool = try DatabasePool(path: path)
        defer { try? pool.close() }
        return try await pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM listening_stats") ?? 0
        }
    }

    // MARK: - Importing from the real fixtures

    @Test func importsSubscriptionsQueueStatsAndLastPlayedFromFixtures() async throws {
        let path = try await makeSeededLegacyDatabase()
        let store = try Store(path: path, legacy: try legacyInput())

        // saved_podcasts.json (3) + podcasts.json (2), deduplicated on feedURL (Show One is in
        // both) -> 4 distinct subscriptions, plus the pre-existing one = 5.
        let podcasts = try await store.podcasts()
        #expect(podcasts.count == 5)
        let titles = Set(podcasts.map(\.title))
        #expect(titles.isSuperset(of: ["Example Show One", "Example Show Two", "Example Show Three", "Example Show Four"]))

        // Only episode 1 and episode 3 exist; episode 2 and 4 are skipped, and file order
        // (1 before 3) is preserved.
        let queue = try await store.queue()
        #expect(queue.map(\.id) == [queuedEpisode1, queuedEpisode3])

        // listening_stats.json has 7 daily logs.
        #expect(try await listeningStatsRowCount(path: path) == 7)

        // lastPlayedEpisodeID lands in settings.
        #expect(try await settingValue(for: "lastPlayedEpisodeID", path: path) == queuedEpisode1.uuidString)
    }

    @Test func importRunsExactlyOnce() async throws {
        let path = try await makeSeededLegacyDatabase()
        let input = try legacyInput()

        _ = try Store(path: path, legacy: input)
        let podcastsAfterFirstOpen = try await Store(path: path, legacy: input).podcasts()
        let countAfterFirstOpen = podcastsAfterFirstOpen.count
        let statsCountAfterFirstOpen = try await listeningStatsRowCount(path: path)

        // Re-opening with the SAME legacy data again must not duplicate anything: v19 is
        // already marked applied, so DatabaseMigrator skips it.
        let store = try Store(path: path, legacy: input)
        let podcastsAfterSecondOpen = try await store.podcasts()

        #expect(podcastsAfterSecondOpen.count == countAfterFirstOpen)
        #expect(try await listeningStatsRowCount(path: path) == statsCountAfterFirstOpen)
        let queueAfterSecondOpen = try await store.queue()
        #expect(queueAfterSecondOpen.map(\.id) == [queuedEpisode1, queuedEpisode3])
    }

    // MARK: - Nil input is a no-op

    @Test func nilLegacyInputImportsNothing() async throws {
        let path = makeTempDatabasePath()
        let store = try Store(path: path, legacy: nil)

        #expect(try await store.podcasts().isEmpty)
        #expect(try await store.queue().isEmpty)
        #expect(try await listeningStatsRowCount(path: path) == 0)
        #expect(try await settingValue(for: "lastPlayedEpisodeID", path: path) == nil)
    }
}
