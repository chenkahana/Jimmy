import Combine
import Foundation
import GRDB
import JimmyKit
import XCTest
@testable import Jimmy

/// Records every `savePlaybackState` call; everything else in `PlaybackStateRepositoryProtocol`
/// is unused by `LegacyProgressMirror` and stubbed out.
private final class RecordingPlaybackStateRepository: PlaybackStateRepositoryProtocol {
    private(set) var savedStates: [PlaybackState] = []

    func savePlaybackState(_ state: PlaybackState) async throws {
        savedStates.append(state)
    }

    func savePlaybackStates(_ states: [PlaybackState]) async throws {
        savedStates.append(contentsOf: states)
    }

    func fetchPlaybackState(for episodeID: UUID) async throws -> PlaybackState? { nil }
    func markFinished(episodeID: UUID) async throws {}
    func fetchAllPlaybackStates() async throws -> [PlaybackState] { [] }
}

/// Returns a single preset episode from `fetchEpisode(by:)`; every other
/// `EpisodeRepositoryProtocol` method is unused by `LegacyProgressMirror` and stubbed out.
private final class StubEpisodeRepository: EpisodeRepositoryProtocol {
    var episode: EpisodeWithPlaybackState?
    let episodeChangesPublisher: AnyPublisher<CleanEpisodeChanges, Never> = Empty().eraseToAnyPublisher()

    func fetchPage(
        podcastID: UUID, cursor: String?, limit: Int, ignoreCache: Bool
    ) async throws -> ([EpisodeWithPlaybackState], nextCursor: String?) {
        ([], nil)
    }

    func fetchPageConditional(
        podcastID: UUID, cursor: String?, limit: Int, etag: String?, lastModified: String?
    ) async throws -> ([EpisodeWithPlaybackState], nextCursor: String?, newEtag: String?, newLastModified: String?)? {
        nil
    }

    func fetchEpisodes(for podcastID: UUID, ignoreCache: Bool) async throws -> [EpisodeWithPlaybackState] { [] }
    func fetchAllEpisodes(for podcastID: UUID, ignoreCache: Bool) async throws -> [EpisodeWithPlaybackState] { [] }

    func fetchEpisode(by episodeID: UUID) async throws -> EpisodeWithPlaybackState? {
        episode?.episode.id == episodeID ? episode : nil
    }

    func saveEpisodes(_ episodes: [EpisodeWithPlaybackState], for podcastID: UUID) async throws {}
    func isStale(podcastID: UUID) -> Bool { false }
}

@MainActor
final class LegacyProgressMirrorTests: XCTestCase {
    private func makeStore() throws -> (store: Store, path: String) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyProgressMirrorTests-\(UUID().uuidString).sqlite")
            .path
        return (try Store(path: path), path)
    }

    /// `progress.episodeID` foreign-keys to `episodes.id`, so `saveProgress` silently no-ops
    /// (`StorePlaybackSource` drops `Store`'s thrown error) unless the episode — and its
    /// podcast — already exist. Same approach as JimmyKit's own `StorePlaybackSourceTests`.
    private func insertEpisode(_ episodeID: UUID, at path: String) async throws {
        let podcastID = UUID()
        let pool = try DatabasePool(path: path)
        try await pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO podcasts (id, title, author, description, feedURL, cleanTitle)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [podcastID.uuidString, "Show", "Author", "", "https://example.com/feed.xml", "Show"]
            )
            try db.execute(
                sql: """
                    INSERT INTO episodes (id, podcastID, title, played, isNew, playbackPosition, page)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [episodeID.uuidString, podcastID.uuidString, "Episode", false, true, 0.0, 1]
            )
        }
    }

    func testSaveProgressAlwaysMirrorsPositionIntoPlaybackState() async throws {
        let (store, path) = try makeStore()
        let playbackStateRepository = RecordingPlaybackStateRepository()
        let episodeRepository = StubEpisodeRepository()
        var markedPlayed: [Jimmy.Episode] = []
        let mirror = LegacyProgressMirror(
            store: store,
            playbackStateRepository: playbackStateRepository,
            episodeRepository: episodeRepository,
            markEpisodePlayed: { markedPlayed.append($0) }
        )

        let episodeID = UUID()
        try await insertEpisode(episodeID, at: path)
        let progress = JimmyKit.Progress(episodeID: episodeID, position: 42, duration: 1_200, isFinished: false)
        await mirror.saveProgress(progress)

        XCTAssertEqual(playbackStateRepository.savedStates.count, 1)
        XCTAssertEqual(playbackStateRepository.savedStates.first?.position, 42)
        XCTAssertEqual(playbackStateRepository.savedStates.first?.finished, false)
        XCTAssertTrue(markedPlayed.isEmpty, "not finished yet, so nothing should be marked played")

        let loaded = await mirror.loadProgress(for: episodeID)
        XCTAssertEqual(loaded?.position, 42, "the save still goes through to the real progress store too")
    }

    func testFinishedProgressMarksTheEpisodePlayedExactlyOnce() async throws {
        let (store, path) = try makeStore()
        let playbackStateRepository = RecordingPlaybackStateRepository()
        let episodeRepository = StubEpisodeRepository()
        let episodeID = UUID()
        try await insertEpisode(episodeID, at: path)
        episodeRepository.episode = EpisodeWithPlaybackState(
            episode: Jimmy.Episode(id: episodeID, title: "Episode"),
            playbackState: PlaybackState(episodeID: episodeID, position: 0, finished: false)
        )
        var markedPlayed: [Jimmy.Episode] = []
        let mirror = LegacyProgressMirror(
            store: store,
            playbackStateRepository: playbackStateRepository,
            episodeRepository: episodeRepository,
            markEpisodePlayed: { markedPlayed.append($0) }
        )

        let finished = JimmyKit.Progress(episodeID: episodeID, position: 1_200, duration: 1_200, isFinished: true)
        await mirror.saveProgress(finished)

        XCTAssertEqual(markedPlayed.map(\.id), [episodeID])

        // Mark the stub episode played, the way the real `EpisodeService` would have, so a second
        // save for the same (still-finished) episode doesn't re-fire the notification.
        episodeRepository.episode?.episode.status.insert(.played)
        await mirror.saveProgress(finished)
        XCTAssertEqual(markedPlayed.count, 1, "already played — shouldn't mark it again")
    }
}
