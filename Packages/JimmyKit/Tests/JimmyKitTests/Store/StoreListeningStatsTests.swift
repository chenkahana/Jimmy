import Foundation
import GRDB
import Testing
@testable import JimmyKit

/// `Store`'s listening-stats surface: logging seconds and the aggregates derived from them.
struct StoreListeningStatsTests {
    private func makeStore() throws -> Store {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("jimmykit-stats-\(UUID().uuidString).sqlite")
            .path
        return try Store(path: path)
    }

    @Test func addListeningSecondsIsANoOpForNonPositiveDurations() async throws {
        let store = try makeStore()
        try await store.addListeningSeconds(0, podcastID: nil)
        try await store.addListeningSeconds(-5, podcastID: nil)

        #expect(try await store.totalListeningSeconds() == 0)
        #expect(try await store.listeningStatsByDay().isEmpty)
    }

    @Test func totalListeningSecondsSumsAcrossDaysAndPodcasts() async throws {
        let store = try makeStore()
        let podcastID = UUID()
        let today = Date()
        let yesterday = Date(timeIntervalSinceNow: -86_400)

        try await store.addListeningSeconds(60, podcastID: podcastID, on: today)
        try await store.addListeningSeconds(30, podcastID: nil, on: today)
        try await store.addListeningSeconds(90, podcastID: podcastID, on: yesterday)

        #expect(try await store.totalListeningSeconds() == 180)
    }

    @Test func listeningStatsByDaySumsSeveralLogsOnTheSameDay() async throws {
        let store = try makeStore()
        let date = Date()

        try await store.addListeningSeconds(10, podcastID: UUID(), on: date)
        try await store.addListeningSeconds(20, podcastID: UUID(), on: date)

        let byDay = try await store.listeningStatsByDay()
        #expect(byDay.count == 1)
        #expect(byDay.first?.date == Store.dayString(date))
        #expect(byDay.first?.seconds == 30)
    }

    @Test func topPodcastsByListeningTimeRanksByTotalSecondsDescending() async throws {
        let store = try makeStore()
        let quiet = UUID()
        let loud = UUID()

        try await store.addListeningSeconds(60, podcastID: quiet)
        try await store.addListeningSeconds(500, podcastID: loud)
        try await store.addListeningSeconds(100, podcastID: loud)

        let top = try await store.topPodcastsByListeningTime(limit: 5)
        #expect(top.first?.podcastID == loud)
        #expect(top.first?.seconds == 600)
        #expect(top.last?.podcastID == quiet)
    }

    @Test func episodesCompletedCountReflectsFinishedProgressRows() async throws {
        let store = try makeStore()
        let feedURL = URL(string: "https://example.com/feed.xml")!
        let podcast = try await store.subscribe(feedURL: feedURL, parsed: ParsedFeed(podcast: .init(), episodes: []))
        let finished = Episode(podcastID: podcast.id, title: "Finished")
        let unplayed = Episode(podcastID: podcast.id, title: "Unplayed")
        try await store.pool.write { db in
            try finished.insert(db)
            try unplayed.insert(db)
        }
        try await store.saveProgress(Progress(episodeID: finished.id, position: 300, isFinished: true))

        #expect(try await store.episodesCompletedCount() == 1)
    }
}
