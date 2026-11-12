import XCTest
@testable import Jimmy
import JimmyKit

/// Discover's recent searches, and the view model's record of which query its results belong to.
final class RecentSearchesTests: XCTestCase {
    func testAddPutsNewestFirstAndDropsCaseInsensitiveDuplicate() {
        var searches = RecentSearches(storage: "")
        searches.add("Planet Money")
        searches.add("Radiolab")
        searches.add("planet money")

        XCTAssertEqual(searches.queries, ["planet money", "Radiolab"])
    }

    func testKeepsOnlyTheNewestEight() {
        var searches = RecentSearches(storage: "")
        for number in 1...10 {
            searches.add("Query \(number)")
        }

        XCTAssertEqual(searches.queries.count, RecentSearches.limit)
        XCTAssertEqual(searches.queries.first, "Query 10")
        XCTAssertEqual(searches.queries.last, "Query 3")
    }

    func testClearRemovesEverything() {
        var searches = RecentSearches(storage: "One\nTwo")
        searches.clear()

        XCTAssertEqual(searches.queries, [])
        XCTAssertEqual(searches.storage, "")
    }

    func testNewlinesBecomeSpacesAndBlankQueriesAreIgnored() {
        var searches = RecentSearches(storage: "")
        searches.add("  hard\nfork  ")
        searches.add(" \n ")

        XCTAssertEqual(searches.queries, ["hard fork"])
        XCTAssertEqual(RecentSearches(storage: searches.storage), searches)
    }
}

@MainActor
final class DiscoverySearchStateTests: XCTestCase {
    private func makeViewModel(
        _ response: @escaping @Sendable (URLRequest) -> LibraryStubURLProtocol.Response
    ) -> DiscoveryViewModel {
        LibraryStubURLProtocol.handler = response
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryStubURLProtocol.self]
        return DiscoveryViewModel(directory: PodcastDirectory(session: URLSession(configuration: configuration)))
    }

    func testEmptyResultRecordsTheCompletedQuery() async {
        let viewModel = makeViewModel { _ in .ok(Data(#"{"resultCount":0,"results":[]}"#.utf8)) }
        defer { LibraryStubURLProtocol.handler = nil }
        viewModel.searchText = "  qzxqv "

        await viewModel.searchPodcasts()

        XCTAssertEqual(viewModel.lastCompletedQuery, "qzxqv")
        XCTAssertEqual(viewModel.searchResults.count, 0)
        XCTAssertNil(viewModel.searchErrorMessage)
        XCTAssertFalse(viewModel.isSearching)
    }

    func testFailedSearchSetsItsOwnErrorAndLeavesTheChartErrorAlone() async {
        let viewModel = makeViewModel { _ in .httpError(statusCode: 500) }
        defer { LibraryStubURLProtocol.handler = nil }
        viewModel.errorMessage = "Charts failed"
        viewModel.searchText = "planet money"

        await viewModel.searchPodcasts()
        XCTAssertEqual(viewModel.lastCompletedQuery, "planet money")
        XCTAssertNotNil(viewModel.searchErrorMessage)

        viewModel.searchText = ""
        await viewModel.searchPodcasts()
        XCTAssertNil(viewModel.searchErrorMessage)
        XCTAssertEqual(viewModel.errorMessage, "Charts failed")
    }
}
