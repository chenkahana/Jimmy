import Foundation
import Testing
@testable import JimmyKit

/// See the serialization note on `StubbedNetworkTests` (FeedFetcherTests.swift) — this
/// extension's tests share that same suite and its stubbed-network state.
extension StubbedNetworkTests {
    private func makeDirectory() -> PodcastDirectory {
        PodcastDirectory(session: .stubbed())
    }

    @Test func searchReturnsDecodedResults() async throws {
        let body = try DiscoverFixtures.data("search_planet_money.json")
        StubURLProtocol.handler = { _ in .ok(data: body) }

        let results = try await makeDirectory().search(query: "planet money")

        #expect(results.count == 2)
        #expect(results[0].title == "Planet Money")
        #expect(results[0].author == "NPR")
        #expect(results[0].feedURL == URL(string: "https://feeds.example.com/planet-money.rss")!)
        #expect(results[0].artworkURL == URL(string: "https://example.com/art600.jpg")!)
        #expect(results[0].genre == "Business")
        #expect(results[0].trackCount == 123)
        #expect(results[1].artworkURL == nil)
        #expect(results[1].description == nil)
    }

    @Test func searchEncodesTheQuery() async throws {
        let body = try DiscoverFixtures.data("search_planet_money.json")
        let capturedRequest = LockedBox<URLRequest?>(nil)
        StubURLProtocol.handler = { request in
            capturedRequest.set(request)
            return .ok(data: body)
        }

        _ = try await makeDirectory().search(query: "  planet money  ")

        let url = capturedRequest.get()?.url?.absoluteString ?? ""
        #expect(url.contains("term=planet"))
        #expect(url.contains("media=podcast"))
        #expect(url.contains("entity=podcast"))
    }

    @Test func emptyQueryReturnsNoResultsWithoutNetworking() async throws {
        StubURLProtocol.handler = { _ in
            Issue.record("should not hit the network for an empty query")
            return .status(500)
        }

        let results = try await makeDirectory().search(query: "   ")
        #expect(results.isEmpty)
    }

    @Test func hebrewQueryTriesIsraeliStoreFirst() async throws {
        let body = try DiscoverFixtures.data("search_planet_money.json")
        let emptyBody = Data(#"{"resultCount":0,"results":[]}"#.utf8)
        let seenURLs = LockedBox<[String]>([])
        StubURLProtocol.handler = { request in
            let urlString = request.url?.absoluteString ?? ""
            seenURLs.set(seenURLs.get() + [urlString])
            if urlString.contains("country=IL") {
                return .ok(data: body)
            }
            return .ok(data: emptyBody)
        }

        let results = try await makeDirectory().search(query: "פלנט מאני")

        #expect(results.count == 2)
        #expect(seenURLs.get().first?.contains("country=IL") == true)
    }

    @Test func searchFallsBackToTheGlobalStoreWhenTheFirstComesBackEmpty() async throws {
        let body = try DiscoverFixtures.data("search_planet_money.json")
        let emptyBody = Data(#"{"resultCount":0,"results":[]}"#.utf8)
        StubURLProtocol.handler = { request in
            if request.url?.absoluteString.contains("country=IL") == true {
                return .ok(data: emptyBody)
            }
            return .ok(data: body)
        }

        let results = try await makeDirectory().search(query: "פלנט מאני")
        #expect(results.count == 2)
    }

    @Test func searchThrowsOnServerError() async throws {
        StubURLProtocol.handler = { _ in .status(500) }

        await #expect(throws: PodcastDirectoryError.http(statusCode: 500)) {
            _ = try await makeDirectory().search(query: "planet money")
        }
    }

    @Test func topChartEntriesDecodesTheChartFeedAndSkipsMalformedIDs() async throws {
        let body = try DiscoverFixtures.data("top_charts.json")
        StubURLProtocol.handler = { _ in .ok(data: body) }

        let entries = try await makeDirectory().topChartEntries(limit: 50)

        #expect(entries.count == 3)
        #expect(entries[0].id == 1_200_000_010)
        #expect(entries[0].name == "Chart Show One")
        #expect(entries[0].artistName == "Artist One")
        #expect(entries[0].artworkURL == URL(string: "https://example.com/chart1/600x600.jpg")!)
        #expect(entries[2].artworkURL == nil)
    }

    @Test func lookupDecodesFullMetadataByID() async throws {
        let body = try DiscoverFixtures.data("lookup.json")
        StubURLProtocol.handler = { _ in .ok(data: body) }

        let results = try await makeDirectory().lookup(ids: [1_200_000_010, 1_200_000_011])

        #expect(results.count == 2)
        #expect(results[0].title == "Chart Show One")
        #expect(results[0].genre == "Comedy")
        #expect(results[0].trackCount == 42)
        #expect(results[1].artworkURL == nil)
    }

    @Test func lookupWithNoIDsReturnsEmptyWithoutNetworking() async throws {
        StubURLProtocol.handler = { _ in
            Issue.record("should not hit the network for an empty id list")
            return .status(500)
        }

        let results = try await makeDirectory().lookup(ids: [])
        #expect(results.isEmpty)
    }
}
