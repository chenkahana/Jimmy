import Foundation
import GRDB
import Testing
@testable import JimmyKit

/// `Store`'s podcast-subscription surface (`observePodcasts`, `subscribe`, `unsubscribe`,
/// `apply`) — the Library screen's entire read/write path onto the database.
struct StoreLibraryTests {
    private func makeStore() throws -> (store: Store, path: String) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("jimmykit-library-\(UUID().uuidString).sqlite")
            .path
        return (try Store(path: path), path)
    }

    private func parseFixture(_ filename: String, feedURL: URL) throws -> ParsedFeed {
        let data = try FeedFixtures.data(filename)
        let podcastID = FeedIDs.generatePodcastID(from: feedURL)
        return try FeedParser.parse(data: data, podcastID: podcastID, feedURL: feedURL)
    }

    // MARK: - subscribe

    @Test func subscribeInsertsThePodcastAndItsEpisodes() async throws {
        let (store, _) = try makeStore()
        let feedURL = URL(string: "https://libsyn-example.libsyn.com/feed.xml")!
        let parsed = try parseFixture("04_libsyn_style_basic.xml", feedURL: feedURL)

        let podcast = try await store.subscribe(feedURL: feedURL, parsed: parsed)

        #expect(podcast.title == "Libsyn Example Show")
        #expect(podcast.feedURL == feedURL)
        #expect(podcast.id == FeedIDs.generatePodcastID(from: feedURL))

        let episodes = try await store.episodes(podcastID: podcast.id)
        #expect(episodes.count == 2)
    }

    @Test func subscribeIsIdempotentOnFeedURL() async throws {
        let (store, _) = try makeStore()
        let feedURL = URL(string: "https://libsyn-example.libsyn.com/feed.xml")!
        let parsed = try parseFixture("04_libsyn_style_basic.xml", feedURL: feedURL)

        let first = try await store.subscribe(feedURL: feedURL, parsed: parsed)
        let second = try await store.subscribe(feedURL: feedURL, parsed: parsed)

        #expect(first.id == second.id)
        let allPodcasts = try await store.podcasts()
        #expect(allPodcasts.count == 1)
    }

    // MARK: - unsubscribe

    @Test func unsubscribeDeletesThePodcastAndCascadesToEverythingThatReferencesItsEpisodes() async throws {
        let (store, _) = try makeStore()
        let feedURL = URL(string: "https://libsyn-example.libsyn.com/feed.xml")!
        let parsed = try parseFixture("04_libsyn_style_basic.xml", feedURL: feedURL)
        let podcast = try await store.subscribe(feedURL: feedURL, parsed: parsed)
        let episodeID = try await store.episodes(podcastID: podcast.id)[0].id

        try await store.enqueue(episodeID, at: 1)
        try await store.saveProgress(Progress(episodeID: episodeID, position: 12, duration: 300, isFinished: false))

        try await store.unsubscribe(podcast.id)

        let remainingPodcasts = try await store.podcasts()
        #expect(remainingPodcasts.isEmpty)
        let remainingEpisodes = try await store.episodes(podcastID: podcast.id)
        #expect(remainingEpisodes.isEmpty)
        let remainingQueue = try await store.queue()
        #expect(remainingQueue.isEmpty)
        let remainingProgress = try await store.progress(for: episodeID)
        #expect(remainingProgress == nil)
    }

    // MARK: - apply

    @Test func applyNotModifiedIsANoOp() async throws {
        let (store, _) = try makeStore()
        let feedURL = URL(string: "https://libsyn-example.libsyn.com/feed.xml")!
        let parsed = try parseFixture("04_libsyn_style_basic.xml", feedURL: feedURL)
        let podcast = try await store.subscribe(feedURL: feedURL, parsed: parsed)

        let inserted = try await store.apply(
            FeedRefreshOutcome(podcastID: podcast.id, result: .success(.notModified))
        )

        #expect(inserted.isEmpty)
        let episodes = try await store.episodes(podcastID: podcast.id)
        #expect(episodes.count == 2)
    }

    @Test func applyUpdatedInsertsOnlyGenuinelyNewEpisodesAndLeavesExistingOnesUntouched() async throws {
        let (store, path) = try makeStore()
        let feedURL = URL(string: "https://libsyn-example.libsyn.com/feed.xml")!
        let parsed = try parseFixture("04_libsyn_style_basic.xml", feedURL: feedURL)
        let podcast = try await store.subscribe(feedURL: feedURL, parsed: parsed)
        let firstEpisodeID = try await store.episodes(podcastID: podcast.id).first!.id

        // Mark the first episode as played, the way the legacy app still would, to prove a
        // refresh never touches it.
        let pool = try DatabasePool(path: path)
        try await pool.write { db in
            try db.execute(sql: "UPDATE episodes SET played = 1 WHERE id = ?", arguments: [firstEpisodeID.uuidString])
        }
        try pool.close()

        // Re-parse the same fixture (same two episodes — nothing new) plus one appended item.
        var reparsed = parsed
        let newEpisode = Episode(
            id: UUID(),
            podcastID: podcast.id,
            title: "Episode 3: Brand New",
            audioURL: URL(string: "https://example.com/libsyn/episode-003.mp3"),
            publishedDate: Date()
        )
        reparsed.episodes.append(newEpisode)

        let outcome = FeedRefreshOutcome(
            podcastID: podcast.id,
            result: .success(.updated(reparsed, etag: "\"abc123\"", lastModified: nil))
        )
        let inserted = try await store.apply(outcome)

        #expect(inserted == [newEpisode.id])

        let episodes = try await store.episodes(podcastID: podcast.id)
        #expect(episodes.count == 3)

        // The pre-existing episode's legacy `played` flag (set above, outside anything `apply`
        // writes) survived the refresh untouched.
        let pool2 = try DatabasePool(path: path)
        let stillPlayed = try await pool2.read { db in
            try Bool.fetchOne(db, sql: "SELECT played FROM episodes WHERE id = ?", arguments: [firstEpisodeID.uuidString])
        }
        try pool2.close()
        #expect(stillPlayed == true)

        let updatedPodcast = try await store.podcasts().first { $0.id == podcast.id }
        #expect(updatedPodcast?.etag == "\"abc123\"")
    }

    @Test func applyFailureIsANoOp() async throws {
        let (store, _) = try makeStore()
        let feedURL = URL(string: "https://libsyn-example.libsyn.com/feed.xml")!
        let parsed = try parseFixture("04_libsyn_style_basic.xml", feedURL: feedURL)
        let podcast = try await store.subscribe(feedURL: feedURL, parsed: parsed)

        let inserted = try await store.apply(
            FeedRefreshOutcome(podcastID: podcast.id, result: .failure(.fetch(underlying: "offline")))
        )

        #expect(inserted.isEmpty)
        let episodes = try await store.episodes(podcastID: podcast.id)
        #expect(episodes.count == 2)
    }

    // MARK: - observePodcasts

    @Test func observePodcastsSortsByLatestEpisodeDateThenTitle() async throws {
        let (store, _) = try makeStore()

        let olderFeedURL = URL(string: "https://example.com/older.xml")!
        var olderFeed = try parseFixture("04_libsyn_style_basic.xml", feedURL: olderFeedURL)
        olderFeed.podcast.title = "Z Show"
        for index in olderFeed.episodes.indices {
            olderFeed.episodes[index].publishedDate = Date(timeIntervalSince1970: 1_000)
        }
        _ = try await store.subscribe(feedURL: olderFeedURL, parsed: olderFeed)

        let newerFeedURL = URL(string: "https://example.com/newer.xml")!
        var newerFeed = try parseFixture("04_libsyn_style_basic.xml", feedURL: newerFeedURL)
        newerFeed.podcast.title = "A Show"
        for index in newerFeed.episodes.indices {
            newerFeed.episodes[index].publishedDate = Date(timeIntervalSince1970: 2_000)
        }
        _ = try await store.subscribe(feedURL: newerFeedURL, parsed: newerFeed)

        var iterator = store.observePodcasts().makeAsyncIterator()
        let podcasts = try await iterator.next()

        #expect(podcasts?.map(\.title) == ["A Show", "Z Show"])
    }
}
