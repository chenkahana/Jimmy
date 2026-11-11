import Foundation
import GRDB
import Testing
@testable import JimmyKit

/// `Store`'s smart-playlist surface: the seeded `playlists` rows and the rule-filtered episode
/// queries that back them.
struct StorePlaylistsTests {
    private func makeStore() throws -> Store {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("jimmykit-playlists-\(UUID().uuidString).sqlite")
            .path
        return try Store(path: path)
    }

    private func makePodcast(_ store: Store) async throws -> Podcast {
        let feedURL = URL(string: "https://example.com/feed-\(UUID().uuidString).xml")!
        return try await store.subscribe(
            feedURL: feedURL,
            parsed: ParsedFeed(podcast: .init(title: "Test Podcast"), episodes: [])
        )
    }

    @Test func playlistsReturnsTheFiveSeededSmartPlaylists() async throws {
        let store = try makeStore()
        let playlists = try await store.playlists()

        #expect(Set(playlists.map(\.rule)) == Set(PlaylistRule.allCases))
        #expect(playlists.count == 5)
    }

    @Test func recentlyAddedReturnsEveryEpisodeNewestFirst() async throws {
        let store = try makeStore()
        let podcast = try await makePodcast(store)
        let older = Episode(podcastID: podcast.id, title: "Older", publishedDate: Date(timeIntervalSince1970: 1_000))
        let newer = Episode(podcastID: podcast.id, title: "Newer", publishedDate: Date(timeIntervalSince1970: 2_000))
        try await store.pool.write { db in
            try older.insert(db)
            try newer.insert(db)
        }

        let items = try await store.episodes(matching: .recentlyAdded)
        #expect(items.map(\.episode.title) == ["Newer", "Older"])
        #expect(try await store.episodeCount(matching: .recentlyAdded) == 2)
    }

    @Test func starredOnlyReturnsStarredEpisodes() async throws {
        let store = try makeStore()
        let podcast = try await makePodcast(store)
        let starred = Episode(podcastID: podcast.id, title: "Starred", starred: true)
        let notStarred = Episode(podcastID: podcast.id, title: "Not starred", starred: false)
        try await store.pool.write { db in
            try starred.insert(db)
            try notStarred.insert(db)
        }

        let items = try await store.episodes(matching: .starred)
        #expect(items.map(\.episode.title) == ["Starred"])
        #expect(try await store.episodeCount(matching: .starred) == 1)
    }

    @Test func unplayedExcludesFinishedEpisodes() async throws {
        let store = try makeStore()
        let podcast = try await makePodcast(store)
        let finished = Episode(podcastID: podcast.id, title: "Finished")
        let unplayed = Episode(podcastID: podcast.id, title: "Unplayed")
        try await store.pool.write { db in
            try finished.insert(db)
            try unplayed.insert(db)
        }
        try await store.saveProgress(Progress(episodeID: finished.id, position: 300, isFinished: true))

        let items = try await store.episodes(matching: .unplayed)
        #expect(items.map(\.episode.title) == ["Unplayed"])
        #expect(try await store.episodeCount(matching: .unplayed) == 1)
    }

    @Test func inProgressOnlyReturnsEpisodesWithUnfinishedPositiveProgress() async throws {
        let store = try makeStore()
        let podcast = try await makePodcast(store)
        let inProgress = Episode(podcastID: podcast.id, title: "In progress")
        let notStarted = Episode(podcastID: podcast.id, title: "Not started")
        try await store.pool.write { db in
            try inProgress.insert(db)
            try notStarted.insert(db)
        }
        try await store.saveProgress(Progress(episodeID: inProgress.id, position: 42, isFinished: false))

        let items = try await store.episodes(matching: .inProgress)
        #expect(items.map(\.episode.title) == ["In progress"])
        #expect(try await store.episodeCount(matching: .inProgress) == 1)
    }

    @Test func downloadedOnlyReturnsEpisodesWithADoneDownload() async throws {
        let store = try makeStore()
        let podcast = try await makePodcast(store)
        let downloaded = Episode(podcastID: podcast.id, title: "Downloaded")
        let notDownloaded = Episode(podcastID: podcast.id, title: "Not downloaded")
        try await store.pool.write { db in
            try downloaded.insert(db)
            try notDownloaded.insert(db)
        }
        try await store.saveDownload(Download(episodeID: downloaded.id, relativePath: "Downloads/x.mp3", state: .done))

        let items = try await store.episodes(matching: .downloaded)
        #expect(items.map(\.episode.title) == ["Downloaded"])
        #expect(try await store.episodeCount(matching: .downloaded) == 1)
    }
}
