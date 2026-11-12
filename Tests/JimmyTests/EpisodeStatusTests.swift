import XCTest
#if canImport(JimmyUtilities)
@testable import JimmyUtilities
#else
@testable import Jimmy
#endif

/// Characterization tests for the EpisodeStatus OptionSet (Jimmy/Models/Episode.swift).
///
/// Note: the "> 95% complete -> mark played" threshold that actually flips an episode's
/// persisted status lives inside a private closure of AudioPlayerService's periodic time
/// observer, driven by a live AVPlayer. It is not reachable as a pure function and is not
/// exercised here. A second, UI-facing "finished" threshold does exist as a pure static
/// function — EpisodeWithStatus.deriveStatus in Jimmy/Models/EpisodeWithPlaybackState.swift —
/// and is covered below. Today: that one uses `>= 0.95`, not `> 0.95` like AudioPlayerService.
///
/// The DB-backed "what marking finished does to playback position" tests that used to live here
/// (against `GRDBPlaybackStateRepository`) were removed along with that repository — the same
/// rule is covered by JimmyKit's `Store.markPlayed`/`.markUnplayed` tests now.
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
}
