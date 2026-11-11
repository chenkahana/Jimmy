import XCTest
@testable import JimmyKit
@testable import Jimmy

/// `LocalAudioImporter` — the file-copy and store-insert path for audio shared to or opened by
/// the app (replaces `BulletproofAudioImporter`/`SharedAudioImporter`), including the relative
/// `audioURL` playback needs to resolve it later (see `AppModel.resolveAudioURL`), and the fix for
/// #86 (imported local-file episodes not showing up in their show's episode list).
@MainActor
final class LocalAudioImporterTests: XCTestCase {
    private func makeTempDatabasePath() -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalAudioImporterTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("jimmy.db").path
    }

    /// A source file outside the app container, the way a share-sheet or "Open In" URL arrives.
    private func makeSourceAudioFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalAudioImporterTests-source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Recording.m4a")
        try Data("fake audio bytes".utf8).write(to: url)
        return url
    }

    override func tearDown() {
        AppModel.current = nil
        super.tearDown()
    }

    func testImportFileCreatesAnEpisodeOfTheImportedAudioShowWithARelativeAudioURL() async throws {
        let model = AppModel(databasePath: makeTempDatabasePath())
        AppModel.current = model
        let sourceURL = try makeSourceAudioFile()
        let title = "Imported Recording \(UUID().uuidString)"

        let importedEpisode = await LocalAudioImporter.shared.importFile(from: sourceURL, title: title)
        let episode = try XCTUnwrap(importedEpisode)
        defer { try? FileManager.default.removeItem(at: resolvedAudioURL(for: episode)) }

        XCTAssertEqual(episode.title, title)
        XCTAssertEqual(episode.podcastID, LocalAudioImporter.importedAudioPodcastID)
        // No scheme: a path relative to the app container, not an absolute remote URL.
        XCTAssertNil(episode.audioURL?.scheme)

        let stored = try await model.readyStore?.episodes(podcastID: LocalAudioImporter.importedAudioPodcastID)
        XCTAssertEqual(stored?.map(\.title), [title])

        XCTAssertTrue(FileManager.default.fileExists(atPath: resolvedAudioURL(for: episode).path))
    }

    func testSecondImportLandsOnTheSameShowAsTheFirst() async throws {
        let model = AppModel(databasePath: makeTempDatabasePath())
        AppModel.current = model
        let firstTitle = "First \(UUID().uuidString)"
        let secondTitle = "Second \(UUID().uuidString)"

        let firstSourceURL = try makeSourceAudioFile()
        let importedFirst = await LocalAudioImporter.shared.importFile(from: firstSourceURL, title: firstTitle)
        let first = try XCTUnwrap(importedFirst)
        let secondSourceURL = try makeSourceAudioFile()
        let importedSecond = await LocalAudioImporter.shared.importFile(from: secondSourceURL, title: secondTitle)
        let second = try XCTUnwrap(importedSecond)
        defer {
            try? FileManager.default.removeItem(at: resolvedAudioURL(for: first))
            try? FileManager.default.removeItem(at: resolvedAudioURL(for: second))
        }

        XCTAssertEqual(first.podcastID, second.podcastID)
        let podcasts = try await model.readyStore?.podcasts()
        XCTAssertEqual(podcasts?.filter { $0.id == LocalAudioImporter.importedAudioPodcastID }.count, 1)
    }

    private func resolvedAudioURL(for episode: JimmyKit.Episode) -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDirectory.appendingPathComponent(episode.audioURL?.path ?? "")
    }
}
