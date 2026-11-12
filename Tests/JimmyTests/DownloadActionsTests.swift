import XCTest
@testable import JimmyKit
@testable import Jimmy

/// The download wiring added to `CurrentPlayViewModel` (Now Playing) and `EpisodeDetailViewModel`
/// (episode detail): both forward to `AppModel`'s `Downloads` (see `AppModel+Downloads.swift`)
/// rather than simulating progress locally, and map `JimmyKit.DownloadState` back for their views.
/// Each `AppModel` here opens its own temporary database with an ephemeral `URLSession` (see
/// `AppModel.makeDownloads`, which picks `.ephemeral` under `XCTestConfigurationFilePath`), so
/// nothing here touches the real app database or a real background session.
@MainActor
final class DownloadActionsTests: XCTestCase {
    private func makeTempDatabasePath() -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadActionsTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("jimmy.db").path
    }

    /// Inserts a podcast and one episode (with an `audioURL`, so `Downloads.download` doesn't
    /// no-op) directly via raw SQL, mirroring `AppModelEpisodesTests.insertEpisode`.
    private func insertEpisode(into model: AppModel) async throws -> UUID {
        let store = try XCTUnwrap(model.readyStore)
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
                arguments: [episodeID.uuidString, podcastID.uuidString, "Test Episode", "https://example.com/audio.mp3", Date()]
            )
        }
        return episodeID
    }

    override func tearDown() {
        AppModel.current = nil
        super.tearDown()
    }

    // MARK: - CurrentPlayViewModel (Now Playing)

    func testCurrentPlayViewModelDownloadEpisodeStartsADownloadThroughAppModel() async throws {
        let model = AppModel(databasePath: makeTempDatabasePath())
        AppModel.current = model
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model)
        let fetchedEpisode = await model.episode(id: episodeID)
        let episode = try XCTUnwrap(fetchedEpisode).asLegacyEpisode()

        let viewModel = CurrentPlayViewModel.shared
        XCTAssertNil(viewModel.downloadState(for: episode))

        viewModel.downloadEpisode(episode)

        XCTAssertEqual(viewModel.downloadState(for: episode), .downloading)
        XCTAssertEqual(viewModel.downloadProgress(for: episode), 0)
    }

    func testCurrentPlayViewModelCancelDownloadClearsStateAndProgress() async throws {
        let model = AppModel(databasePath: makeTempDatabasePath())
        AppModel.current = model
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model)
        let fetchedEpisode = await model.episode(id: episodeID)
        let episode = try XCTUnwrap(fetchedEpisode).asLegacyEpisode()

        let viewModel = CurrentPlayViewModel.shared
        viewModel.downloadEpisode(episode)
        XCTAssertEqual(viewModel.downloadState(for: episode), .downloading)

        viewModel.cancelDownload(episode)

        XCTAssertNil(viewModel.downloadState(for: episode))
        XCTAssertNil(viewModel.downloadProgress(for: episode))
    }

    func testCurrentPlayViewModelDeleteDownloadClearsStateAndProgress() async throws {
        let model = AppModel(databasePath: makeTempDatabasePath())
        AppModel.current = model
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model)
        let fetchedEpisode = await model.episode(id: episodeID)
        let episode = try XCTUnwrap(fetchedEpisode).asLegacyEpisode()

        let viewModel = CurrentPlayViewModel.shared
        viewModel.downloadEpisode(episode)
        XCTAssertEqual(viewModel.downloadState(for: episode), .downloading)

        viewModel.deleteDownload(episode)

        XCTAssertNil(viewModel.downloadState(for: episode))
        XCTAssertNil(viewModel.downloadProgress(for: episode))
    }

    // MARK: - EpisodeDetailViewModel

    func testEpisodeDetailViewModelDownloadEpisodeStartsADownloadThroughAppModel() async throws {
        let model = AppModel(databasePath: makeTempDatabasePath())
        AppModel.current = model
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model)
        let fetchedEpisode = await model.episode(id: episodeID)
        let episode = try XCTUnwrap(fetchedEpisode).asLegacyEpisode()

        let viewModel = EpisodeDetailViewModel(episode: episode)
        XCTAssertNil(viewModel.downloadState)

        viewModel.downloadEpisode()

        XCTAssertEqual(viewModel.downloadState, .downloading)
        XCTAssertEqual(viewModel.downloadProgress, 0)
    }

    func testEpisodeDetailViewModelCancelDownloadClearsStateAndProgress() async throws {
        let model = AppModel(databasePath: makeTempDatabasePath())
        AppModel.current = model
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model)
        let fetchedEpisode = await model.episode(id: episodeID)
        let episode = try XCTUnwrap(fetchedEpisode).asLegacyEpisode()

        let viewModel = EpisodeDetailViewModel(episode: episode)
        viewModel.downloadEpisode()
        XCTAssertEqual(viewModel.downloadState, .downloading)

        viewModel.cancelDownload()

        XCTAssertNil(viewModel.downloadState)
        XCTAssertNil(viewModel.downloadProgress)
    }

    func testEpisodeDetailViewModelDeleteDownloadClearsStateAndProgress() async throws {
        let model = AppModel(databasePath: makeTempDatabasePath())
        AppModel.current = model
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model)
        let fetchedEpisode = await model.episode(id: episodeID)
        let episode = try XCTUnwrap(fetchedEpisode).asLegacyEpisode()

        let viewModel = EpisodeDetailViewModel(episode: episode)
        viewModel.downloadEpisode()
        XCTAssertEqual(viewModel.downloadState, .downloading)

        viewModel.deleteDownload()

        XCTAssertNil(viewModel.downloadState)
        XCTAssertNil(viewModel.downloadProgress)
    }

    // MARK: - AppModel+Downloads mapping

    func testAppModelDownloadStateAndIsDownloadedReflectDownloadsStates() async throws {
        let model = AppModel(databasePath: makeTempDatabasePath())
        guard case .ready = model.launchState else { return XCTFail("store should open") }
        let episodeID = try await insertEpisode(into: model)
        let fetchedEpisode = await model.episode(id: episodeID)
        let episode = try XCTUnwrap(fetchedEpisode)

        XCTAssertNil(model.downloadState(for: episodeID))
        XCTAssertFalse(model.isDownloaded(episodeID))

        model.download(episode)

        XCTAssertEqual(model.downloadState(for: episodeID), .downloading)
        XCTAssertFalse(model.isDownloaded(episodeID))

        model.cancelDownload(episodeID)

        XCTAssertNil(model.downloadState(for: episodeID))
    }
}
