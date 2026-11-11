import Foundation
import GRDB
import Testing
@testable import JimmyKit

/// `Store`'s read surface for `SuggestionsRanker`'s signals: every `progress` row, and
/// `listening_stats` (created by `v20_legacy_import` even with nothing to import).
struct StoreSuggestionsTests {
    private func makeStore() throws -> (store: Store, path: String) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("jimmykit-suggestions-\(UUID().uuidString).sqlite")
            .path
        return (try Store(path: path), path)
    }

    private func subscribeFixture(_ store: Store) async throws -> Podcast {
        let feedURL = URL(string: "https://libsyn-example.libsyn.com/feed.xml")!
        let podcastID = FeedIDs.generatePodcastID(from: feedURL)
        let data = try FeedFixtures.data("04_libsyn_style_basic.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: podcastID, feedURL: feedURL)
        return try await store.subscribe(feedURL: feedURL, parsed: parsed)
    }

    @Test func allProgressReturnsEverySavedRow() async throws {
        let (store, _) = try makeStore()
        let podcast = try await subscribeFixture(store)
        let episodes = try await store.episodes(podcastID: podcast.id)

        let progress = Progress(episodeID: episodes[0].id, position: 120, duration: 1_800, isFinished: false)
        try await store.saveProgress(progress)

        let all = try await store.allProgress()

        #expect(all.map(\.episodeID) == [progress.episodeID])
        #expect(all.first?.position == 120)
    }

    @Test func allProgressIsEmptyForAFreshStore() async throws {
        let (store, _) = try makeStore()

        #expect(try await store.allProgress().isEmpty)
    }

    @Test func listeningStatsDecodesRowsWithAndWithoutAPodcastID() async throws {
        let (store, path) = try makeStore()
        let podcast = try await subscribeFixture(store)

        let pool = try DatabasePool(path: path)
        try await pool.write { db in
            try db.execute(
                sql: "INSERT INTO listening_stats (id, date, podcastID, seconds) VALUES (?, ?, ?, ?)",
                arguments: [UUID().uuidString, "2026-11-10", podcast.id.uuidString, 900.0]
            )
            try db.execute(
                sql: "INSERT INTO listening_stats (id, date, podcastID, seconds) VALUES (?, ?, ?, ?)",
                arguments: [UUID().uuidString, "2026-11-09", nil, 300.0]
            )
        }
        try pool.close()

        let stats = try await store.listeningStats()

        #expect(stats.count == 2)
        #expect(stats.contains { $0.podcastID == podcast.id && $0.seconds == 900 })
        #expect(stats.contains { $0.podcastID == nil && $0.seconds == 300 })
    }
}
