import XCTest
#if canImport(JimmyUtilities)
@testable import JimmyUtilities
#else
@testable import Jimmy
#endif

/// Characterization tests pinning how the app decodes its legacy on-disk JSON formats
/// TODAY, using the fixtures in Tests/Fixtures/LegacyData. Each test mirrors the exact
/// decoder configuration the app uses at the call site named in the comment.
final class LegacyDataDecodingTests: XCTestCase {
    /// Tests/Fixtures/LegacyData, resolved relative to this source file so it works
    /// unmodified on the simulator (the Mac filesystem is visible from inside it).
    private var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // JimmyTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Fixtures/LegacyData")
    }

    private func load(_ filename: String) throws -> Data {
        try Data(contentsOf: fixturesDirectory.appendingPathComponent(filename))
    }

    // MARK: - saved_podcasts.json (PodcastRepository ~line 147: plain JSONDecoder() -> [Podcast])

    func testSavedPodcastsDecodesWithPlainDecoder() throws {
        let data = try load("saved_podcasts.json")
        let podcasts = try JSONDecoder().decode([Podcast].self, from: data)

        XCTAssertEqual(podcasts.count, 3)
        XCTAssertEqual(podcasts.map(\.title), ["Example Show One", "Example Show Two", "Example Show Three"])
        XCTAssertEqual(podcasts[0].id, UUID(uuidString: "550e8400-e29b-41d4-a716-446655440001"))
        XCTAssertEqual(podcasts[1].autoAddToQueue, true)
        XCTAssertEqual(podcasts[1].notificationsEnabled, true)

        // Plain JSONDecoder() uses .deferredToDate: seconds since 2001-01-01, per fixture README.
        XCTAssertEqual(podcasts[0].lastEpisodeDate, Date(timeIntervalSinceReferenceDate: 728215200.0))
        XCTAssertEqual(podcasts[0].etag, "\"abc123def456\"")

        // Show Three omits artworkURL/lastEpisodeDate/etag/lastFetched entirely.
        XCTAssertNil(podcasts[2].artworkURL)
        XCTAssertNil(podcasts[2].lastEpisodeDate)
        XCTAssertNil(podcasts[2].etag)
        XCTAssertNil(podcasts[2].lastFetched)
    }

    // MARK: - podcasts.json (FileStorage-backed Documents/AppData store: plain JSONDecoder() -> [Podcast])

    func testAppDataPodcastsDecodesWithPlainDecoder() throws {
        let data = try load("podcasts.json")
        let podcasts = try JSONDecoder().decode([Podcast].self, from: data)

        XCTAssertEqual(podcasts.count, 2)
        XCTAssertEqual(podcasts.map(\.title), ["Example Show One", "Example Show Four"])

        // Today: this file is not deduplicated against saved_podcasts.json by the decoder —
        // "Example Show One" (id 550e...0001) appears in both fixtures; deduplication, if any,
        // happens later in PodcastRepository.checkAndMigrateIfNeeded via a seenFeedURLs set.
        XCTAssertEqual(podcasts[0].id, UUID(uuidString: "550e8400-e29b-41d4-a716-446655440001"))
        XCTAssertEqual(podcasts[1].id, UUID(uuidString: "550e8400-e29b-41d4-a716-446655440004"))
    }

    // MARK: - episode_queue.json (QueueViewModel ~line 126 legacy fallback: plain JSONDecoder() -> [Episode])

    func testEpisodeQueueDecodesWithPlainDecoder() throws {
        let data = try load("episode_queue.json")
        let episodes = try JSONDecoder().decode([Episode].self, from: data)

        XCTAssertEqual(episodes.count, 4)

        let episode1 = episodes[0]
        XCTAssertEqual(episode1.title, "Episode 1: Getting Started")
        XCTAssertEqual(episode1.playbackPosition, 0)
        // Today: the fixture's "played" bool (false) and "status" bitmask (1 = played) disagree.
        // A plain decode does not reconcile them — that only happens via the v14 database
        // migration's UPDATE statements, which never run against this JSON.
        XCTAssertFalse(episode1.played)
        XCTAssertTrue(episode1.status.contains(.played))

        let episode2 = episodes[1]
        XCTAssertEqual(episode2.playbackPosition, 1200)
        XCTAssertTrue(episode2.played)

        let episode3 = episodes[2]
        XCTAssertTrue(episode3.starred)
        // status 3 = played (1) | queued (2)
        XCTAssertEqual(episode3.status, [.played, .queued])

        let episode4 = episodes[3]
        XCTAssertEqual(episode4.duration, 3600)
        XCTAssertEqual(episode4.playbackPosition, 3600)
        XCTAssertEqual(episode4.playbackPosition, episode4.duration) // fully played

        // Plain JSONDecoder() uses .deferredToDate for publishedDate too.
        XCTAssertEqual(episode1.publishedDate, Date(timeIntervalSinceReferenceDate: 728215200.0))
    }

    // listening_stats.json's decode shape is pinned by JimmyKit's own
    // `LegacyImportTests.importsSubscriptionsQueueStatsAndLastPlayedFromFixtures()` now — the
    // legacy `ListeningStats` model (and the service that decoded it) is gone; JimmyKit's
    // `v20_legacy_import` migration decodes this fixture directly.
}
