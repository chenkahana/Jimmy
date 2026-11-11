import XCTest
@testable import Jimmy
import JimmyKit

final class AssistantEpisodeMatcherTests: XCTestCase {
    func testMatchesByEpisodeTitleFirst() {
        let target = JimmyKit.Episode.fixture(title: "Sleep Science 101")
        let other = JimmyKit.Episode.fixture(title: "Unrelated Episode")

        let match = AssistantEpisodeMatcher.bestMatch(for: "sleep", episodes: [other, target], podcasts: [])

        XCTAssertEqual(match, target)
    }

    func testFallsBackToTheNewestEpisodeOfAMatchingShow() {
        let podcast = JimmyKit.Podcast.fixture(title: "The Daily")
        let older = JimmyKit.Episode.fixture(
            title: "Episode A", podcastID: podcast.id, publishedDate: Date(timeIntervalSince1970: 100)
        )
        let newer = JimmyKit.Episode.fixture(
            title: "Episode B", podcastID: podcast.id, publishedDate: Date(timeIntervalSince1970: 200)
        )

        let match = AssistantEpisodeMatcher.bestMatch(for: "daily", episodes: [older, newer], podcasts: [podcast])

        XCTAssertEqual(match, newer)
    }

    func testMatchIsCaseInsensitive() {
        let target = JimmyKit.Episode.fixture(title: "The Big News Show")

        let match = AssistantEpisodeMatcher.bestMatch(for: "BIG NEWS", episodes: [target], podcasts: [])

        XCTAssertEqual(match, target)
    }

    func testReturnsNilWhenNothingMatches() {
        let episode = JimmyKit.Episode.fixture(title: "Anything")

        XCTAssertNil(AssistantEpisodeMatcher.bestMatch(for: "nonexistent", episodes: [episode], podcasts: []))
    }

    func testBlankQueryReturnsNilRatherThanMatchingEverything() {
        let episode = JimmyKit.Episode.fixture(title: "Anything")

        XCTAssertNil(AssistantEpisodeMatcher.bestMatch(for: "   ", episodes: [episode], podcasts: []))
    }
}
