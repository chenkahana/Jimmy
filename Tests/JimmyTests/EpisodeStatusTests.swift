import XCTest
import GRDB
#if canImport(JimmyUtilities)
@testable import JimmyUtilities
#else
@testable import Jimmy
#endif

/// Characterization tests for the EpisodeStatus OptionSet (Jimmy/Models/Episode.swift) and
/// for what the playback-state layer does to position when an episode is marked finished
/// (Jimmy/Data/Repositories/GRDBRepositories.swift, GRDBPlaybackStateRepository).
///
/// Note: the "> 95% complete -> mark played" threshold that actually flips an episode's
/// persisted status lives inside a private closure of AudioPlayerService's periodic time
/// observer, driven by a live AVPlayer. It is not reachable as a pure function and is not
/// exercised here. A second, UI-facing "finished" threshold does exist as a pure static
/// function — EpisodeWithStatus.deriveStatus in Jimmy/Models/EpisodeWithPlaybackState.swift —
/// and is covered below. Today: that one uses `>= 0.95`, not `> 0.95` like AudioPlayerService.
final class EpisodeStatusTests: XCTestCase {
    // MARK: - Pure OptionSet rules

    func testIndividualFlagRawValues() {
        XCTAssertEqual(EpisodeStatus.played.rawValue, 1)
        XCTAssertEqual(EpisodeStatus.queued.rawValue, 2)
        XCTAssertEqual(EpisodeStatus.playing.rawValue, 4)
    }

    func testCombinedFlagsAreIndependentBits() {
        let combo: EpisodeStatus = [.played, .queued]
        XCTAssertEqual(combo.rawValue, 3)
        XCTAssertTrue(combo.contains(.played))
        XCTAssertTrue(combo.contains(.queued))
        XCTAssertFalse(combo.contains(.playing))
    }

    func testAllThreeFlagsCanBeSetTogether() {
        let all: EpisodeStatus = [.played, .queued, .playing]
        XCTAssertEqual(all.rawValue, 7)
    }

    func testInsertAndRemoveAreIndependentOfOtherBits() {
        var status: EpisodeStatus = [.queued, .playing]
        status.insert(.played)
        XCTAssertEqual(status.rawValue, 7)

        status.remove(.playing)
        XCTAssertEqual(status, [.played, .queued])
    }

    func testDefaultEpisodeStatusIsEmpty() {
        let episode = Episode(title: "Untitled")
        XCTAssertEqual(episode.status.rawValue, 0)
        XCTAssertFalse(episode.status.contains(.played))
    }

    func testStatusEncodesAndDecodesAsABareIntegerNotAnObject() throws {
        // Today: EpisodeStatus is Codable via the compiler's RawRepresentable-aware
        // synthesis, so it round-trips as a plain JSON number (e.g. `1`), not as
        // `{"rawValue":1}`. This matches the legacy fixtures, which store status as a bare int.
        let status: EpisodeStatus = [.played, .queued]
        let data = try JSONEncoder().encode(status)
        XCTAssertEqual(String(data: data, encoding: .utf8), "3")

        let decoded = try JSONDecoder().decode(EpisodeStatus.self, from: Data("3".utf8))
        XCTAssertEqual(decoded, status)
    }

    // MARK: - EpisodeWithStatus.deriveStatus (pure "finished" rule, Jimmy/Models/EpisodeWithPlaybackState.swift)

    private var sampleEpisode: Episode { Episode(title: "Episode") }

    func testDeriveStatusPrioritizesPlayingOverEverythingElse() {
        let status = EpisodeWithStatus.deriveStatus(
            episode: sampleEpisode, playProgress: 1.0, isQueued: true, isCurrentlyPlaying: true
        )
        XCTAssertEqual(status, .playing)
    }

    func testDeriveStatusPrioritizesQueuedOverPlayed() {
        let status = EpisodeWithStatus.deriveStatus(
            episode: sampleEpisode, playProgress: 1.0, isQueued: true, isCurrentlyPlaying: false
        )
        XCTAssertEqual(status, .queued)
    }

    func testDeriveStatusTreats95PercentProgressAsPlayedInclusive() {
        // Today: this threshold is `>= 0.95`, exactly 0.95 counts as played.
        let atThreshold = EpisodeWithStatus.deriveStatus(
            episode: sampleEpisode, playProgress: 0.95, isQueued: false, isCurrentlyPlaying: false
        )
        XCTAssertEqual(atThreshold, .played)

        let justBelow = EpisodeWithStatus.deriveStatus(
            episode: sampleEpisode, playProgress: 0.949, isQueued: false, isCurrentlyPlaying: false
        )
        XCTAssertEqual(justBelow, .none)
    }

    func testDeriveStatusTreatsEpisodeStatusPlayedFlagAsPlayedRegardlessOfProgress() {
        var played = Episode(title: "Episode")
        played.status.insert(.played)

        let status = EpisodeWithStatus.deriveStatus(
            episode: played, playProgress: 0.0, isQueued: false, isCurrentlyPlaying: false
        )
        XCTAssertEqual(status, .played)
    }

    // MARK: - What marking an episode finished does to playback position (DB-backed rule)

    private func makeIsolatedRepository() async throws -> (DatabaseManager, GRDBPlaybackStateRepository) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("episode-status-tests-\(UUID().uuidString).sqlite").path
        let dbManager = try await DatabaseManager(path: path)
        return (dbManager, GRDBPlaybackStateRepository(dbManager: dbManager))
    }

    private func insertPodcastAndEpisode(dbManager: DatabaseManager, episodeID: UUID) async throws {
        let podcast = Podcast(title: "Show", author: "Author", feedURL: URL(string: "https://example.com/feed.xml")!)
        let episode = Episode(id: episodeID, title: "Episode", podcastID: podcast.id)
        try await dbManager.writeAsync { db in
            try podcast.save(db)
            try episode.save(db)
        }
    }

    func testMarkFinishedResetsPositionToZeroRegardlessOfPriorProgress() async throws {
        let (dbManager, repository) = try await makeIsolatedRepository()
        let episodeID = UUID()
        try await insertPodcastAndEpisode(dbManager: dbManager, episodeID: episodeID)

        try await repository.savePlaybackState(PlaybackState(episodeID: episodeID, position: 842.5, finished: false))
        try await repository.markFinished(episodeID: episodeID)

        let state = try await repository.fetchPlaybackState(for: episodeID)
        // Today: markFinished always resets position to 0, it does not preserve the
        // last-known playback position the way EpisodeService.updatePlaybackStateAsFinished
        // does (which keeps currentState.position).
        XCTAssertEqual(state?.position, 0)
        XCTAssertEqual(state?.finished, true)
    }

    func testSavePlaybackStateAlsoSyncsEpisodesPlaybackPositionColumn() async throws {
        let (dbManager, repository) = try await makeIsolatedRepository()
        let episodeID = UUID()
        try await insertPodcastAndEpisode(dbManager: dbManager, episodeID: episodeID)

        try await repository.savePlaybackState(PlaybackState(episodeID: episodeID, position: 123.0, finished: false))

        // Today: saving playback state is not limited to the playback_state table — it also
        // writes episodes.playbackPosition directly, keeping the two in sync.
        let storedPosition: Double? = try await dbManager.readAsync { db in
            try Double.fetchOne(db, sql: "SELECT playbackPosition FROM episodes WHERE id = ?", arguments: [episodeID.uuidString])
        }
        XCTAssertEqual(storedPosition, 123.0)
    }

    func testMarkingFinishedDoesNotTouchEpisodeStatusOrPlayedFlag() async throws {
        let (dbManager, repository) = try await makeIsolatedRepository()
        let episodeID = UUID()
        try await insertPodcastAndEpisode(dbManager: dbManager, episodeID: episodeID)

        try await repository.markFinished(episodeID: episodeID)

        // Today: GRDBPlaybackStateRepository.markFinished only ever touches the
        // playback_state table (and episodes.playbackPosition via savePlaybackState) — it
        // never sets episodes.played or episodes.status. Only EpisodeService.setEpisodePlayed
        // does that, as a separate step.
        let played: Bool? = try await dbManager.readAsync { db in
            try Bool.fetchOne(db, sql: "SELECT played FROM episodes WHERE id = ?", arguments: [episodeID.uuidString])
        }
        let status: Int? = try await dbManager.readAsync { db in
            try Int.fetchOne(db, sql: "SELECT status FROM episodes WHERE id = ?", arguments: [episodeID.uuidString])
        }
        XCTAssertEqual(played, false)
        XCTAssertEqual(status, 0)
    }
}
