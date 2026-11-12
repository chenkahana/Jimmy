import XCTest
import JimmyKit
@testable import Jimmy

final class LibraryNewEpisodeCountTests: XCTestCase {
    private let followed = Date(timeIntervalSince1970: 1_000_000)

    private func podcast() -> JimmyKit.Podcast {
        JimmyKit.Podcast(
            title: "Show",
            cleanTitle: "Show",
            author: "Author",
            feedURL: URL(fileURLWithPath: "/feed.xml"),
            createdAt: followed
        )
    }

    private func item(
        _ podcast: JimmyKit.Podcast,
        publishedOffset: TimeInterval,
        position: TimeInterval? = nil,
        finished: Bool = false
    ) -> JimmyKit.EpisodeListItem {
        let episode = JimmyKit.Episode(
            podcastID: podcast.id,
            title: "Episode",
            publishedDate: followed.addingTimeInterval(publishedOffset)
        )
        let progress = position.map {
            JimmyKit.Progress(episodeID: episode.id, position: $0, duration: 100, isFinished: finished, updatedAt: followed)
        }
        return JimmyKit.EpisodeListItem(episode: episode, progress: progress)
    }

    func testCountsOnlyUntouchedEpisodesPublishedAfterFollowing() {
        let show = podcast()
        let items = [
            item(show, publishedOffset: -60),                    // back catalog
            item(show, publishedOffset: 60),                     // new
            item(show, publishedOffset: 120),                    // new
            item(show, publishedOffset: 180, position: 30),      // started
            item(show, publishedOffset: 240, position: 0, finished: true) // marked played
        ]

        let counts = LibraryShowCell.newEpisodeCounts(episodes: items, podcasts: [show])

        XCTAssertEqual(counts[show.id], 2)
    }

    func testShowWithoutNewEpisodesHasNoCount() {
        let show = podcast()

        let counts = LibraryShowCell.newEpisodeCounts(episodes: [item(show, publishedOffset: -60)], podcasts: [show])

        XCTAssertNil(counts[show.id])
    }

    func testEachShowIsCountedSeparatelyAndTheFollowMomentIsNotNew() {
        let first = podcast()
        let second = podcast()
        let items = [
            item(first, publishedOffset: 0),     // published as it was followed
            item(first, publishedOffset: 60),
            item(second, publishedOffset: 60),
            item(second, publishedOffset: 120)
        ]

        let counts = LibraryShowCell.newEpisodeCounts(episodes: items, podcasts: [first, second])

        XCTAssertEqual(counts[first.id], 1)
        XCTAssertEqual(counts[second.id], 2)
    }
}
