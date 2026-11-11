import XCTest
@testable import JimmyKit
@testable import Jimmy

/// `SubscriptionImporter` — parses each subscription-export format with JimmyKit's `Import/`
/// parsers and subscribes to every feed found, through a real `AppModel` whose network is
/// stubbed (`LibraryStubURLProtocol`, shared with `AppModelLibraryTests`) so each `subscribe(
/// feedURL:)` call is real but never touches the network.
@MainActor
final class SubscriptionImporterTests: XCTestCase {
    private func makeTempDatabasePath() -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubscriptionImporterTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("jimmy.db").path
    }

    private func makeModel() -> AppModel {
        let feedXML = Self.minimalFeedXML
        LibraryStubURLProtocol.handler = { _ in .ok(feedXML) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryStubURLProtocol.self]
        let fetcher = FeedFetcher(session: URLSession(configuration: configuration))
        return AppModel(databasePath: makeTempDatabasePath(), feedFetcher: fetcher)
    }

    private static var minimalFeedXML: Data {
        Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel><title>Show</title></channel></rss>
            """.utf8)
    }

    private func waitForPodcastCount(_ model: AppModel, toEqual count: Int, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if model.podcasts.count == count { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.podcasts.count, count)
    }

    override func tearDown() {
        AppModel.current = nil
        super.tearDown()
    }

    func testOPMLSubscribesToEveryFeed() async throws {
        let model = makeModel()
        AppModel.current = model
        let opml = Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="1.0"><body>
              <outline text="Show One" xmlUrl="https://example.com/opml-one.xml" />
              <outline text="Show Two" xmlUrl="https://example.com/opml-two.xml" />
            </body></opml>
            """.utf8)

        let outcome = try await SubscriptionImporter.importSubscriptions(from: opml, format: .opml)

        XCTAssertEqual(outcome.importedCount, 2)
        await waitForPodcastCount(model, toEqual: 2)
    }

    func testAppleBulkJSONSubscribesToItsFeedURLEntry() async throws {
        let model = makeModel()
        AppModel.current = model
        let json = Data("""
            [{"title":"Show","feedUrl":"https://example.com/apple-bulk.xml","author":"Someone"}]
            """.utf8)

        let outcome = try await SubscriptionImporter.importSubscriptions(from: json, format: .appleBulkJSON)

        XCTAssertEqual(outcome.importedCount, 1)
        await waitForPodcastCount(model, toEqual: 1)
    }

    func testGoogleTakeoutSubscribesToItsFeedURLEntry() async throws {
        let model = makeModel()
        AppModel.current = model
        let json = Data("""
            {"subscriptions":[{"title":"Show","feedUrl":"https://example.com/takeout.xml"}]}
            """.utf8)

        let outcome = try await SubscriptionImporter.importSubscriptions(from: json, format: .googleTakeout)

        XCTAssertEqual(outcome.importedCount, 1)
        await waitForPodcastCount(model, toEqual: 1)
    }

    func testSpotifyListSubscribesToEveryFeedURLLine() async throws {
        let model = makeModel()
        AppModel.current = model
        let text = Data("https://example.com/spotify-one.xml\nhttps://example.com/spotify-two.xml\n".utf8)

        let outcome = try await SubscriptionImporter.importSubscriptions(from: text, format: .spotifyList)

        XCTAssertEqual(outcome.importedCount, 2)
        await waitForPodcastCount(model, toEqual: 2)
    }

    func testAlreadySubscribedFeedIsSkippedRatherThanDuplicated() async throws {
        let model = makeModel()
        AppModel.current = model
        _ = try await model.subscribe(feedURL: URL(string: "https://example.com/opml-one.xml")!)
        await waitForPodcastCount(model, toEqual: 1)

        let opml = Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="1.0"><body>
              <outline text="Show One" xmlUrl="https://example.com/opml-one.xml" />
            </body></opml>
            """.utf8)
        let outcome = try await SubscriptionImporter.importSubscriptions(from: opml, format: .opml)

        XCTAssertEqual(outcome.importedCount, 0)
        await waitForPodcastCount(model, toEqual: 1)
    }
}
