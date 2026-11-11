import Foundation
import GRDB
import Testing
@testable import JimmyKit

/// `Store.addLocalEpisode(_:to:)` — the write path for locally imported audio files, which have
/// no feed to `subscribe(feedURL:parsed:)` to.
struct StoreLocalEpisodeTests {
    private func makeStore() throws -> Store {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("jimmykit-local-\(UUID().uuidString).sqlite")
            .path
        return try Store(path: path)
    }

    private func importedAudioPodcast() -> Podcast {
        Podcast(
            id: FeedIDs.generatePodcastID(from: URL(string: "jimmy-local://imported-audio")!),
            title: "Imported audio",
            cleanTitle: "Imported audio",
            author: "Local Files",
            feedURL: URL(string: "jimmy-local://imported-audio")!
        )
    }

    @Test func firstImportCreatesThePodcastAndTheEpisode() async throws {
        let store = try makeStore()
        let podcast = importedAudioPodcast()
        // Percent-encoded, the way `LocalAudioImporter` builds it — a raw space would make
        // `URL(string:)` return `nil` outright.
        let episode = Episode(
            podcastID: podcast.id,
            title: "My Recording",
            audioURL: URL(string: "ImportedAudio/My%20Recording.mp3")
        )

        try await store.addLocalEpisode(episode, to: podcast)

        let podcasts = try await store.podcasts()
        #expect(podcasts.map(\.id) == [podcast.id])
        let episodes = try await store.episodes(podcastID: podcast.id)
        #expect(episodes.map(\.title) == ["My Recording"])
        // A relative path round-trips with no scheme, so playback can resolve it against the
        // app container rather than treating it as an absolute remote URL.
        #expect(episodes.first?.audioURL?.scheme == nil)
        #expect(episodes.first?.audioURL?.path == "ImportedAudio/My Recording.mp3")
    }

    @Test func secondImportReusesTheSamePodcastRatherThanDuplicatingIt() async throws {
        let store = try makeStore()
        let podcast = importedAudioPodcast()
        let first = Episode(podcastID: podcast.id, title: "First", audioURL: URL(string: "ImportedAudio/First.mp3"))
        let second = Episode(podcastID: podcast.id, title: "Second", audioURL: URL(string: "ImportedAudio/Second.mp3"))

        try await store.addLocalEpisode(first, to: podcast)
        try await store.addLocalEpisode(second, to: podcast)

        let podcasts = try await store.podcasts()
        #expect(podcasts.count == 1)
        let episodes = try await store.episodes(podcastID: podcast.id)
        #expect(Set(episodes.map(\.title)) == ["First", "Second"])
    }
}
