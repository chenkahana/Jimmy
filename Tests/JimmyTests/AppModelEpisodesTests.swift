import XCTest
@testable import JimmyKit
@testable import Jimmy

/// `AppModel`'s episode-detail surface added in PR 18 (`Jimmy/App/AppModel+Episodes.swift`):
/// one-shot episode/progress reads, the `observeEpisodes` live stream, mark played/unplayed, and
/// bookmarks/transcript/chapters — all read and written straight through `Store`. Each test opens
/// its own temporary on-disk database via `AppModel`'s normal init, exactly like
/// `AppModelLibraryTests`, so nothing here touches the real app database.
@MainActor
final class AppModelEpisodesTests: XCTestCase {
    private func makeTempDatabasePath() -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModelEpisodesTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("jimmy.db").path
    }

    private func makeModel() -> AppModel {
        let configuration = URLSessionConfiguration.ephemeral
        let fetcher = FeedFetcher(session: URLSession(configuration: configuration))
        return AppModel(databasePath: makeTempDatabasePath(), feedFetcher: fetcher)
    }

    /// Inserts a podcast and one episode directly via raw SQL (bypassing feed-fetching), and
    /// returns the episode's ID. Mirrors the minimal legacy-table shape `Store` reads from.
    private func insertEpisode(into model: AppModel, title: String = "Test Episode") async throws -> UUID {
        let store = model.readyStore!
        let podcastID = UUID()
        let episodeID = UUID()
        try await store.pool.write { db in
            try db.execute(
                sql: """
                INSERT INTO podcasts (id, title, author, feedURL, artworkURL, autoAddToQueue)
                VALUES (?, ?, ?, ?, ?, 0)
                """,
                arguments: [podcastID.uuidString, "Test Podcast", "Author", "https://example.com/feed.xml", nil]
            )
            try db.execute(
                sql: """
                INSERT INTO episodes (id, podcastID, title, audioURL, publishedDate)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [episodeID.uuidString, podcastID.uuidString, title, "https://example.com/audio.mp3", Date()]
            )
        }
        return episodeID
    }

    // MARK: - episode / progress

    func testEpisodeReturnsTheStoredEpisodeByID() async throws {
        let model = makeModel()
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model, title: "Hello World")

        let episode = await model.episode(id: episodeID)

        XCTAssertEqual(episode?.title, "Hello World")
    }

    func testEpisodeReturnsNilForAnUnknownID() async throws {
        let model = makeModel()
        guard case .ready = model.launchState else { return XCTFail("store should open") }

        let episode = await model.episode(id: UUID())

        XCTAssertNil(episode)
    }

    func testProgressIsNilBeforeAnythingIsRecorded() async throws {
        let model = makeModel()
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model)

        let progress = await model.progress(for: episodeID)

        XCTAssertNil(progress)
    }

    // MARK: - markPlayed / markUnplayed

    func testMarkPlayedThenProgressReportsFinished() async throws {
        let model = makeModel()
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model)

        await model.markPlayed(episodeID)

        let progress = await model.progress(for: episodeID)
        XCTAssertEqual(progress?.isFinished, true)
    }

    func testMarkUnplayedAfterMarkPlayedClearsFinishedButKeepsPosition() async throws {
        let model = makeModel()
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model)
        try await model.readyStore!.pool.write { db in
            try db.execute(
                sql: "INSERT INTO progress (episodeID, position, isFinished, updatedAt) VALUES (?, ?, 0, ?)",
                arguments: [episodeID.uuidString, 42.0, Date()]
            )
        }

        await model.markPlayed(episodeID)
        await model.markUnplayed(episodeID)

        let progress = await model.progress(for: episodeID)
        XCTAssertEqual(progress?.isFinished, false)
        XCTAssertEqual(progress?.position, 42.0)
    }

    // MARK: - observeEpisodes

    func testObserveEpisodesStreamsTheInsertedEpisode() async throws {
        let model = makeModel()
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model, title: "Streamed Episode")

        guard let stream = model.observeEpisodes(podcastID: nil) else {
            return XCTFail("store should be ready")
        }

        var found: EpisodeListItem?
        for try await items in stream {
            if let match = items.first(where: { $0.episode.id == episodeID }) {
                found = match
                break
            }
        }

        XCTAssertEqual(found?.episode.title, "Streamed Episode")
    }

    // MARK: - Bookmarks

    func testAddBookmarkThenListReturnsIt() async throws {
        let model = makeModel()
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model)

        let addedBookmark = await model.addBookmark(episodeID: episodeID, timestamp: 90, note: "Great point")
        let added = try XCTUnwrap(addedBookmark)
        let bookmarks = await model.bookmarks(for: episodeID)

        XCTAssertEqual(added.timestamp, 90)
        XCTAssertEqual(bookmarks.count, 1)
        XCTAssertEqual(bookmarks.first?.id, added.id)
        XCTAssertEqual(bookmarks.first?.note, "Great point")
    }

    func testDeleteBookmarkRemovesIt() async throws {
        let model = makeModel()
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model)
        let addedBookmark = await model.addBookmark(episodeID: episodeID, timestamp: 10)
        let added = try XCTUnwrap(addedBookmark)

        await model.deleteBookmark(added.id)

        let bookmarks = await model.bookmarks(for: episodeID)
        XCTAssertTrue(bookmarks.isEmpty)
    }

    // MARK: - Transcript

    func testSaveTranscriptThenLoadRoundTrips() async throws {
        let model = makeModel()
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model)
        let transcript = Transcript(
            episodeID: episodeID,
            url: URL(string: "https://example.com/transcript.srt")!,
            format: .srt,
            segments: [TranscriptSegment(startTime: 0, endTime: 5, text: "Hello")]
        )

        await model.saveTranscript(transcript)
        let loaded = await model.transcript(for: episodeID)

        XCTAssertEqual(loaded?.url, transcript.url)
        XCTAssertEqual(loaded?.format, .srt)
    }

    func testTranscriptIsNilWhenNoneSaved() async throws {
        let model = makeModel()
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model)

        let loaded = await model.transcript(for: episodeID)

        XCTAssertNil(loaded)
    }

    // MARK: - Chapters

    func testSaveChaptersThenLoadRoundTrips() async throws {
        let model = makeModel()
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model)
        let chapters = [
            Chapter(start: 0, title: "Intro"),
            Chapter(start: 120, title: "Main Topic")
        ]

        await model.saveChapters(chapters, for: episodeID)
        let loaded = await model.chapters(for: episodeID)

        XCTAssertEqual(loaded.map(\.title), ["Intro", "Main Topic"])
    }

    func testChaptersAreEmptyWhenNoneSaved() async throws {
        let model = makeModel()
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model)

        let loaded = await model.chapters(for: episodeID)

        XCTAssertTrue(loaded.isEmpty)
    }
}
