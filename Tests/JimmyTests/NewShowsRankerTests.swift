import XCTest
@testable import Jimmy

/// `NewShowsRanker.rank` merges each seed's search results into one list: round-robin across
/// seeds, skipping subscribed feeds and anything already picked.
final class NewShowsRankerTests: XCTestCase {
    private func show(_ name: String) -> SuggestedShowResult {
        SuggestedShowResult(title: name, author: "Author", feedURL: URL(string: "https://example.com/\(name)")!, artworkURL: nil)
    }

    func testRoundRobinsAcrossSeedsInsteadOfExhaustingOneSeedFirst() {
        let seedA = [show("A1"), show("A2")]
        let seedB = [show("B1"), show("B2")]

        let results = NewShowsRanker.rank(resultsBySeed: [seedA, seedB], subscribedFeedURLs: [])

        XCTAssertEqual(results.map(\.title), ["A1", "B1", "A2", "B2"])
    }

    func testExcludesAlreadySubscribedShows() {
        let subscribed = show("Subscribed")
        let fresh = show("Fresh")

        let results = NewShowsRanker.rank(resultsBySeed: [[subscribed, fresh]], subscribedFeedURLs: [subscribed.feedURL])

        XCTAssertEqual(results, [fresh])
    }

    func testDedupesTheSameShowAcrossSeeds() {
        let shared = show("Shared")
        let onlyInB = show("OnlyInB")

        let results = NewShowsRanker.rank(resultsBySeed: [[shared], [shared, onlyInB]], subscribedFeedURLs: [])

        XCTAssertEqual(results, [shared, onlyInB])
    }

    func testHonorsTheLimit() {
        let seedA = (0..<5).map { show("A\($0)") }

        let results = NewShowsRanker.rank(resultsBySeed: [seedA], subscribedFeedURLs: [], limit: 2)

        XCTAssertEqual(results.count, 2)
    }

    func testEmptySeedsReturnsEmpty() {
        XCTAssertTrue(NewShowsRanker.rank(resultsBySeed: [], subscribedFeedURLs: []).isEmpty)
    }
}
