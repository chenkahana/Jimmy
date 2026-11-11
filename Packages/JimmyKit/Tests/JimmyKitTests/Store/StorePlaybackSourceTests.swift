import Foundation
import GRDB
import Testing
@testable import JimmyKit

/// `StorePlaybackSource` is what `AppModel` hands `Playback` as its `ProgressStore`/`QueueSource`
/// — proves it round-trips progress and walks queue order the way `Playback` needs, through the
/// real `Store` (not a fake).
struct StorePlaybackSourceTests {
    /// Opens `Store` first (so `v19_progress`'s one-time backfill has no episodes to run
    /// against), then inserts episodes through a second connection — so a fresh episode starts
    /// with no `progress` row at all, letting `loadProgressReturnsNilBeforeAnythingIsSaved`
    /// below tell "never saved" apart from "saved at position 0".
    private func makeStoreWithEpisodes(count: Int) async throws -> (store: Store, episodeIDs: [UUID]) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("jimmykit-playback-source-\(UUID().uuidString).sqlite")
            .path
        let store = try Store(path: path)

        let podcastID = UUID()
        let episodeIDs = (0..<count).map { _ in UUID() }
        let pool = try DatabasePool(path: path)
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

        return (store, episodeIDs)
    }

    @Test func loadProgressReturnsNilBeforeAnythingIsSaved() async throws {
        let (store, ids) = try await makeStoreWithEpisodes(count: 1)
        let source = StorePlaybackSource(store: store)

        #expect(await source.loadProgress(for: ids[0]) == nil)
    }

    @Test func saveProgressThenLoadProgressRoundTrips() async throws {
        let (store, ids) = try await makeStoreWithEpisodes(count: 1)
        let source = StorePlaybackSource(store: store)

        let saved = Progress(episodeID: ids[0], position: 42, duration: 1_200, isFinished: false, updatedAt: Date())
        await source.saveProgress(saved)

        let loaded = await source.loadProgress(for: ids[0])
        #expect(loaded?.position == 42)
        #expect(loaded?.duration == 1_200)
        #expect(loaded?.isFinished == false)
    }

    @Test func episodeAfterNilReturnsTheFirstQueuedEpisode() async throws {
        let (store, ids) = try await makeStoreWithEpisodes(count: 2)
        try await store.enqueue(ids[0], at: 1)
        try await store.enqueue(ids[1], at: 2)
        let source = StorePlaybackSource(store: store)

        #expect(await source.episode(after: nil)?.id == ids[0])
    }

    @Test func episodeAfterAnIDReturnsTheNextQueuedEpisode() async throws {
        let (store, ids) = try await makeStoreWithEpisodes(count: 3)
        try await store.enqueue(ids[0], at: 1)
        try await store.enqueue(ids[1], at: 2)
        try await store.enqueue(ids[2], at: 3)
        let source = StorePlaybackSource(store: store)

        #expect(await source.episode(after: ids[0])?.id == ids[1])
        #expect(await source.episode(after: ids[2])?.id == nil)
    }

    @Test func episodeAfterAnIDNotInTheQueueReturnsTheFirstQueuedEpisode() async throws {
        let (store, ids) = try await makeStoreWithEpisodes(count: 2)
        try await store.enqueue(ids[1], at: 1)
        let source = StorePlaybackSource(store: store)

        #expect(await source.episode(after: ids[0])?.id == ids[1])
    }

    @Test func removeFinishedDequeuesTheEpisode() async throws {
        let (store, ids) = try await makeStoreWithEpisodes(count: 2)
        try await store.enqueue(ids[0], at: 1)
        try await store.enqueue(ids[1], at: 2)
        let source = StorePlaybackSource(store: store)

        await source.removeFinished(ids[0])

        #expect(try await store.queue().map(\.id) == [ids[1]])
    }
}
