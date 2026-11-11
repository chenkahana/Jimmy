import Foundation
import Testing
@testable import JimmyKit

/// Verifies `FeedIDs` produces byte-identical UUIDs to the app's existing
/// `Jimmy/Utilities/DeterministicUUIDGenerator.swift` for the same inputs.
///
/// These expected UUIDs were computed by running a verbatim copy of TODAY's generator
/// (same SHA-256-of-string → first-16-bytes-as-UUID algorithm) against the inputs below,
/// via a throwaway script (not committed). If existing libraries' episode/podcast rows
/// are to keep matching after this PR, `FeedIDs` must keep returning exactly these values.
struct FeedIDsCompatibilityTests {
    static let feedURL = URL(string: "https://example.com/apple-style-feed.xml")!

    @Test func episodeIDFromAudioURL_fixture01Style() {
        let id = FeedIDs.generateEpisodeID(
            feedURL: Self.feedURL,
            audioURL: URL(string: "https://example.com/episodes/001.mp3"),
            title: "Episode 1: Getting Started",
            publishedDate: nil
        )
        #expect(id == UUID(uuidString: "D78D62E7-3798-E882-444C-49BAB4736959"))
    }

    @Test func episodeIDFromAudioURL_m4aExtension() {
        let id = FeedIDs.generateEpisodeID(
            feedURL: Self.feedURL,
            audioURL: URL(string: "https://example.com/buzzsprout/ep1.m4a"),
            title: "Buzzsprout Episode",
            publishedDate: nil
        )
        #expect(id == UUID(uuidString: "D37BD29C-E460-0E0D-E3BE-6858B5BD3BC3"))
    }

    @Test func episodeIDFromAudioURL_unicodeTitleQueryParams() {
        let id = FeedIDs.generateEpisodeID(
            feedURL: Self.feedURL,
            audioURL: URL(string: "https://example.com/hebrew/ep1.mp3?track=1"),
            title: "פרק 1: התחלה",
            publishedDate: nil
        )
        #expect(id == UUID(uuidString: "F8B9EE64-B599-3F9E-60B6-CE3EC2E12C18"))
    }

    @Test func episodeIDFallback_withPublishedDate() {
        let id = FeedIDs.generateEpisodeID(
            feedURL: Self.feedURL,
            audioURL: nil,
            title: "Episode 2: No Audio Yet",
            publishedDate: Date(timeIntervalSince1970: 1_706_000_000)
        )
        #expect(id == UUID(uuidString: "D2A27997-086C-A2BA-93F1-A13D9B4B9D24"))
    }

    @Test func episodeIDFallback_noPublishedDate() {
        let id = FeedIDs.generateEpisodeID(
            feedURL: Self.feedURL,
            audioURL: nil,
            title: "Episode With No Date Or Audio",
            publishedDate: nil
        )
        #expect(id == UUID(uuidString: "0471CCF9-BEBB-AE9F-9E1E-C89911EA1AB1"))
    }

    @Test func podcastIDFromFeedURL() {
        let id = FeedIDs.generatePodcastID(from: Self.feedURL)
        #expect(id == UUID(uuidString: "6FDD90DD-EB28-1950-BCD9-462651755410"))
    }
}
