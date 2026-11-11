import Foundation
import GRDB
import Testing
@testable import JimmyKit

/// `Store`'s episode-detail surface: `episode(id:)`, `observeEpisodes(podcastID:)`,
/// `markPlayed`/`markUnplayed`, bookmarks, transcripts, and chapters — podcast detail, episode
/// rows, and episode detail's entire read/write path onto the database.
struct StoreEpisodesTests {
    private func makeStore() throws -> (store: Store, path: String) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("jimmykit-episodes-\(UUID().uuidString).sqlite")
            .path
        return (try Store(path: path), path)
    }

    private func parseFixture(_ filename: String, feedURL: URL) throws -> ParsedFeed {
        let data = try FeedFixtures.data(filename)
        let podcastID = FeedIDs.generatePodcastID(from: feedURL)
        return try FeedParser.parse(data: data, podcastID: podcastID, feedURL: feedURL)
    }

    private func subscribeFixture(_ store: Store) async throws -> (podcastID: UUID, episodeIDs: [UUID]) {
        let feedURL = URL(string: "https://libsyn-example.libsyn.com/feed.xml")!
        let parsed = try parseFixture("04_libsyn_style_basic.xml", feedURL: feedURL)
        let podcast = try await store.subscribe(feedURL: feedURL, parsed: parsed)
        let episodes = try await store.episodes(podcastID: podcast.id)
        return (podcast.id, episodes.map(\.id))
    }

    // MARK: - episode(id:)

    @Test func episodeByIDReturnsTheStoredEpisode() async throws {
        let (store, _) = try makeStore()
        let (_, episodeIDs) = try await subscribeFixture(store)

        let episode = try await store.episode(id: episodeIDs[0])
        #expect(episode?.id == episodeIDs[0])
    }

    @Test func episodeByIDReturnsNilWhenItDoesNotExist() async throws {
        let (store, _) = try makeStore()
        let episode = try await store.episode(id: UUID())
        #expect(episode == nil)
    }

    // MARK: - observeEpisodes

    @Test func observeEpisodesJoinsProgressQueueAndDownloadState() async throws {
        let (store, _) = try makeStore()
        let (podcastID, episodeIDs) = try await subscribeFixture(store)
        let firstID = episodeIDs[0]

        try await store.saveProgress(Progress(episodeID: firstID, position: 12, duration: 300, isFinished: false))
        try await store.enqueue(firstID, at: 1)
        try await store.saveDownload(Download(episodeID: firstID, relativePath: "Downloads/\(firstID).mp3", state: .done))

        var iterator = store.observeEpisodes(podcastID: podcastID).makeAsyncIterator()
        let items = try await iterator.next()

        let firstItem = items?.first { $0.episode.id == firstID }
        #expect(firstItem?.progress?.position == 12)
        #expect(firstItem?.isQueued == true)
        #expect(firstItem?.downloadState == .done)

        let secondItem = items?.first { $0.episode.id == episodeIDs[1] }
        #expect(secondItem?.progress == nil)
        #expect(secondItem?.isQueued == false)
        #expect(secondItem?.downloadState == nil)
    }

    @Test func observeEpisodesWithNilPodcastIDReturnsEveryEpisodeAcrossTheLibrary() async throws {
        let (store, _) = try makeStore()
        let (_, episodeIDs) = try await subscribeFixture(store)

        let secondFeedURL = URL(string: "https://example.com/other.xml")!
        let secondParsed = try parseFixture("04_libsyn_style_basic.xml", feedURL: secondFeedURL)
        let secondPodcast = try await store.subscribe(feedURL: secondFeedURL, parsed: secondParsed)
        let secondEpisodeIDs = try await store.episodes(podcastID: secondPodcast.id).map(\.id)

        var iterator = store.observeEpisodes(podcastID: nil).makeAsyncIterator()
        let items = try await iterator.next()

        let allIDs = Set(items?.map(\.episode.id) ?? [])
        #expect(allIDs == Set(episodeIDs + secondEpisodeIDs))
    }

    // MARK: - markPlayed / markUnplayed

    @Test func markPlayedCreatesProgressWhenNoneExists() async throws {
        let (store, _) = try makeStore()
        let (_, episodeIDs) = try await subscribeFixture(store)
        let episodeID = episodeIDs[0]

        try await store.markPlayed(episodeID)

        let progress = try await store.progress(for: episodeID)
        #expect(progress?.isFinished == true)
        #expect(progress?.position == 0)
    }

    @Test func markPlayedLeavesPositionUntouched() async throws {
        let (store, _) = try makeStore()
        let (_, episodeIDs) = try await subscribeFixture(store)
        let episodeID = episodeIDs[0]
        try await store.saveProgress(Progress(episodeID: episodeID, position: 123, duration: 600, isFinished: false))

        try await store.markPlayed(episodeID)

        let progress = try await store.progress(for: episodeID)
        #expect(progress?.isFinished == true)
        #expect(progress?.position == 123)
    }

    @Test func markUnplayedClearsIsFinishedButLeavesPosition() async throws {
        let (store, _) = try makeStore()
        let (_, episodeIDs) = try await subscribeFixture(store)
        let episodeID = episodeIDs[0]
        try await store.saveProgress(Progress(episodeID: episodeID, position: 600, duration: 600, isFinished: true))

        try await store.markUnplayed(episodeID)

        let progress = try await store.progress(for: episodeID)
        #expect(progress?.isFinished == false)
        #expect(progress?.position == 600)
    }

    // MARK: - Bookmarks

    @Test func addBookmarkThenListReturnsItOrderedByTimestamp() async throws {
        let (store, _) = try makeStore()
        let (_, episodeIDs) = try await subscribeFixture(store)
        let episodeID = episodeIDs[0]

        _ = try await store.addBookmark(episodeID: episodeID, timestamp: 90, note: "second")
        _ = try await store.addBookmark(episodeID: episodeID, timestamp: 10, note: "first")

        let bookmarks = try await store.bookmarks(for: episodeID)
        #expect(bookmarks.map(\.note) == ["first", "second"])
    }

    @Test func deleteBookmarkRemovesIt() async throws {
        let (store, _) = try makeStore()
        let (_, episodeIDs) = try await subscribeFixture(store)
        let episodeID = episodeIDs[0]
        let bookmark = try await store.addBookmark(episodeID: episodeID, timestamp: 42)

        try await store.deleteBookmark(bookmark.id)

        let bookmarks = try await store.bookmarks(for: episodeID)
        #expect(bookmarks.isEmpty)
    }

    // MARK: - Transcript

    @Test func saveTranscriptThenLoadRoundTrips() async throws {
        let (store, _) = try makeStore()
        let (_, episodeIDs) = try await subscribeFixture(store)
        let episodeID = episodeIDs[0]
        let segments = [TranscriptSegment(startTime: 0, endTime: 5, text: "Hello there")]
        let transcript = Transcript(
            episodeID: episodeID,
            url: URL(string: "https://example.com/transcript.json")!,
            format: .json,
            segments: segments
        )

        try await store.saveTranscript(transcript)

        let loaded = try await store.transcript(for: episodeID)
        #expect(loaded?.url == transcript.url)
        #expect(loaded?.format == .json)
        #expect(loaded?.segments == segments)
    }

    @Test func transcriptReturnsNilWhenNoneSaved() async throws {
        let (store, _) = try makeStore()
        let (_, episodeIDs) = try await subscribeFixture(store)
        let transcript = try await store.transcript(for: episodeIDs[0])
        #expect(transcript == nil)
    }

    // MARK: - Chapters

    @Test func saveChaptersThenLoadRoundTrips() async throws {
        let (store, _) = try makeStore()
        let (_, episodeIDs) = try await subscribeFixture(store)
        let episodeID = episodeIDs[0]
        let chapters = [
            Chapter(start: 0, title: "Intro"),
            Chapter(start: 60, title: "Main topic", url: URL(string: "https://example.com")),
        ]

        try await store.saveChapters(chapters, for: episodeID)

        let loaded = try await store.chapters(for: episodeID)
        #expect(loaded == chapters)
    }

    @Test func chaptersReturnsEmptyWhenNoneSaved() async throws {
        let (store, _) = try makeStore()
        let (_, episodeIDs) = try await subscribeFixture(store)
        let chapters = try await store.chapters(for: episodeIDs[0])
        #expect(chapters.isEmpty)
    }

    @Test func chaptersDecodesThePodcasting20OnDiskFieldNames() async throws {
        let (store, path) = try makeStore()
        let (_, episodeIDs) = try await subscribeFixture(store)
        let episodeID = episodeIDs[0]

        let pool = try DatabasePool(path: path)
        try await pool.write { db in
            try db.execute(
                sql: "INSERT INTO episode_details (episodeID, fullDescription, chaptersJSON) VALUES (?, '', ?)",
                arguments: [episodeID.uuidString, #"[{"startTime":30,"title":"Chapter 1","img":"https://example.com/a.png"}]"#]
            )
        }
        try pool.close()

        let chapters = try await store.chapters(for: episodeID)
        #expect(chapters == [Chapter(start: 30, title: "Chapter 1", imageURL: URL(string: "https://example.com/a.png"))])
    }
}
