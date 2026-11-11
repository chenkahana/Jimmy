import Foundation
import Testing
@testable import JimmyKit

/// Round-trips every model through JSONEncoder/JSONDecoder and checks equality.
struct ModelCodableTests {
    @Test func podcastRoundTrip() throws {
        let value = Podcast(
            title: "Test Show",
            cleanTitle: "Test Show",
            author: "Author",
            description: "A show",
            feedURL: URL(string: "https://example.com/feed.xml")!,
            artworkURL: URL(string: "https://example.com/art.png"),
            autoAddToQueue: true,
            notificationsEnabled: true,
            lastEpisodeDate: Date(timeIntervalSince1970: 1_700_000_000),
            etag: "etag-1",
            lastFetched: Date(timeIntervalSince1970: 1_700_000_100)
        )
        try assertRoundTrip(value)
    }

    @Test func episodeRoundTrip() throws {
        let value = Episode(
            podcastID: UUID(),
            title: "Episode 1",
            audioURL: URL(string: "https://example.com/ep1.mp3"),
            publishedDate: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 1_800,
            artworkURL: URL(string: "https://example.com/ep1.png"),
            description: "Show notes",
            isNew: false,
            page: 2,
            starred: true
        )
        try assertRoundTrip(value)
    }

    @Test func queueEntryRoundTrip() throws {
        try assertRoundTrip(QueueEntry(episodeID: UUID(), position: 3))
    }

    @Test func progressRoundTrip() throws {
        let value = Progress(episodeID: UUID(), position: 120, duration: 600, isFinished: false)
        try assertRoundTrip(value)
    }

    @Test func downloadRoundTrip() throws {
        let value = Download(episodeID: UUID(), relativePath: "abc/ep.mp3", byteCount: 12_345, state: .downloading)
        try assertRoundTrip(value)
    }

    @Test func playlistRoundTrip() throws {
        try assertRoundTrip(Playlist(name: "In Progress", rule: .inProgress))
    }

    @Test func bookmarkRoundTrip() throws {
        let value = Bookmark(episodeID: UUID(), timestamp: 42, note: "Good bit")
        try assertRoundTrip(value)
    }

    @Test func transcriptRoundTrip() throws {
        let segments = [TranscriptSegment(startTime: 0, endTime: 5, text: "Hello", speaker: "A")]
        let value = Transcript(
            episodeID: UUID(),
            url: URL(string: "https://example.com/transcript.json")!,
            format: .json,
            segments: segments
        )
        try assertRoundTrip(value)
    }

    @Test func chapterRoundTrip() throws {
        let value = Chapter(
            start: 30,
            title: "Intro",
            url: URL(string: "https://example.com"),
            imageURL: URL(string: "https://example.com/img.png")
        )
        try assertRoundTrip(value)
    }

    @Test func listeningStatRoundTrip() throws {
        let value = ListeningStat(date: "2026-11-11", podcastID: UUID(), seconds: 900)
        try assertRoundTrip(value)
    }

    @Test func watchNowPlayingRoundTrip() throws {
        let value = WatchNowPlaying(
            episodeID: UUID(),
            title: "Episode 1",
            showTitle: "A Show",
            artworkURL: URL(string: "https://example.com/art.png"),
            position: 42,
            duration: 1_800,
            isPlaying: true,
            rate: 1.5
        )
        try assertRoundTrip(value)
    }

    @Test func watchNowPlayingRoundTripWithoutOptionals() throws {
        let value = WatchNowPlaying(episodeID: UUID(), title: "Episode 1", position: 0, isPlaying: false, rate: 1.0)
        try assertRoundTrip(value)
    }

    @Test func watchEpisodeSummaryRoundTrip() throws {
        try assertRoundTrip(WatchEpisodeSummary(id: UUID(), title: "Episode 1", showTitle: "A Show"))
    }

    @Test func watchSessionStateRoundTrip() throws {
        let value = WatchSessionState(
            nowPlaying: WatchNowPlaying(episodeID: UUID(), title: "Episode 1", position: 10, isPlaying: true, rate: 1.0),
            queue: [WatchEpisodeSummary(id: UUID(), title: "Episode 2", showTitle: "A Show")],
            recent: [WatchEpisodeSummary(id: UUID(), title: "Episode 3")]
        )
        try assertRoundTrip(value)
    }

    @Test func watchSessionStateCapsQueueAndRecentCounts() {
        let queue = (0..<60).map { WatchEpisodeSummary(id: UUID(), title: "Episode \($0)") }
        let recent = (0..<30).map { WatchEpisodeSummary(id: UUID(), title: "Episode \($0)") }
        let value = WatchSessionState(queue: queue, recent: recent)
        #expect(value.queue.count == WatchSessionState.maxQueueCount)
        #expect(value.recent.count == WatchSessionState.maxRecentCount)
    }

    @Test func watchCommandRoundTrip() throws {
        try assertRoundTrip(WatchCommand.play)
        try assertRoundTrip(WatchCommand.pause)
        try assertRoundTrip(WatchCommand.skipForward)
        try assertRoundTrip(WatchCommand.skipBackward)
        try assertRoundTrip(WatchCommand.playEpisode(UUID()))
        try assertRoundTrip(WatchCommand.removeFromQueue(UUID()))
    }
}

private func assertRoundTrip<T: Codable & Equatable>(_ value: T) throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(value)
    let decoded = try decoder.decode(T.self, from: data)
    #expect(decoded == value)
}
