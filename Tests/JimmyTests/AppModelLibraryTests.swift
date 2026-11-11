import XCTest
@testable import JimmyKit
@testable import Jimmy

/// `AppModel`'s library surface (`subscribe`, `unsubscribe`, `refreshAll`/`refresh`) — the
/// Library screen's entire read/write path. Network access goes through a stubbed `URLSession`
/// (`LibraryStubURLProtocol`), the same approach JimmyKit's own feed tests use, so nothing here
/// ever touches the real network.
@MainActor
final class AppModelLibraryTests: XCTestCase {
    private func makeTempDatabasePath() -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModelLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("jimmy.db").path
    }

    private func makeModel(handler: @escaping @Sendable (URLRequest) -> LibraryStubURLProtocol.Response) -> AppModel {
        LibraryStubURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryStubURLProtocol.self]
        let fetcher = FeedFetcher(session: URLSession(configuration: configuration))
        return AppModel(databasePath: makeTempDatabasePath(), feedFetcher: fetcher)
    }

    private func waitForPodcastCount(_ model: AppModel, toEqual count: Int, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if model.podcasts.count == count { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.podcasts.count, count)
    }

    private func waitForQueueCount(_ model: AppModel, toEqual count: Int, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if model.queue.count == count { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.queue.count, count)
    }

    /// `model.podcasts` is kept current by `store.observePodcasts()`'s background task, so a raw
    /// SQL write to the `podcasts` table (bypassing `AppModel`) needs a moment to show up there
    /// before something that reads `model.podcasts` (like `refreshAll()`) can see it.
    private func waitForAutoAddToQueue(_ model: AppModel, podcastID: UUID, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if model.podcasts.first(where: { $0.id == podcastID })?.autoAddToQueue == true { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.podcasts.first(where: { $0.id == podcastID })?.autoAddToQueue, true)
    }

    // MARK: - subscribe

    func testSubscribeFetchesParsesAndStoresThePodcastAndItsEpisodes() async throws {
        let feedURL = URL(string: "https://example.com/feed.xml")!
        let model = makeModel { _ in .ok(Self.feedXML(episodeCount: 2)) }
        guard case .ready = model.launchState else { return XCTFail("store should open") }

        let podcast = try await model.subscribe(feedURL: feedURL)

        XCTAssertEqual(podcast.title, "Sample Show")
        XCTAssertEqual(podcast.feedURL, feedURL)
        await waitForPodcastCount(model, toEqual: 1)
    }

    func testSubscribeIsIdempotentOnFeedURL() async throws {
        let feedURL = URL(string: "https://example.com/feed.xml")!
        let model = makeModel { _ in .ok(Self.feedXML(episodeCount: 2)) }
        guard case .ready = model.launchState else { return XCTFail("store should open") }

        let first = try await model.subscribe(feedURL: feedURL)
        let second = try await model.subscribe(feedURL: feedURL)

        XCTAssertEqual(first.id, second.id)
        await waitForPodcastCount(model, toEqual: 1)
    }

    // MARK: - unsubscribe

    func testUnsubscribeDequeuesEpisodesAndRemovesThePodcast() async throws {
        let feedURL = URL(string: "https://example.com/feed.xml")!
        let model = makeModel { _ in .ok(Self.feedXML(episodeCount: 2)) }
        guard case .ready = model.launchState else { return XCTFail("store should open") }

        let podcast = try await model.subscribe(feedURL: feedURL)
        await waitForPodcastCount(model, toEqual: 1)
        let episodeID = try await model.readyStore!.episodes(podcastID: podcast.id)[0].id
        await model.enqueue(episodeID)
        await waitForQueueCount(model, toEqual: 1)

        await model.unsubscribe(podcast.id)

        await waitForPodcastCount(model, toEqual: 0)
        await waitForQueueCount(model, toEqual: 0)
    }

    // MARK: - refreshAll

    func testRefreshAllAppliesNewEpisodesAndRecordsErrorsSeparately() async throws {
        let workingFeedURL = URL(string: "https://example.com/working.xml")!
        let brokenFeedURL = URL(string: "https://example.com/broken.xml")!

        // Both feeds fetch successfully at subscribe time — `brokenFeedURL` only starts
        // failing once the handler below is swapped in for the refresh.
        let model = makeModel { _ in .ok(Self.feedXML(episodeCount: 1, titlePrefix: "Working")) }
        guard case .ready = model.launchState else { return XCTFail("store should open") }

        _ = try await model.subscribe(feedURL: workingFeedURL)
        _ = try await model.subscribe(feedURL: brokenFeedURL)
        await waitForPodcastCount(model, toEqual: 2)

        // The working feed's second fetch returns one more episode than the first, so the
        // refresh has something genuinely new to insert; the broken feed now fails.
        LibraryStubURLProtocol.handler = { request in
            if request.url == brokenFeedURL {
                return .httpError(statusCode: 500)
            }
            return .ok(Self.feedXML(episodeCount: 2, titlePrefix: "Working"))
        }

        await model.refreshAll()

        let workingPodcastID = model.podcasts.first { $0.feedURL == workingFeedURL }!.id
        let brokenPodcastID = model.podcasts.first { $0.feedURL == brokenFeedURL }!.id

        let episodes = try await model.readyStore!.episodes(podcastID: workingPodcastID)
        XCTAssertEqual(episodes.count, 2)
        XCTAssertNil(model.lastRefreshErrors[workingPodcastID])
        XCTAssertNotNil(model.lastRefreshErrors[brokenPodcastID])
    }

    func testRefreshAllAutoAddsNewEpisodesToQueueWhenEnabled() async throws {
        let feedURL = URL(string: "https://example.com/auto-add.xml")!
        let model = makeModel { _ in .ok(Self.feedXML(episodeCount: 1)) }
        guard case .ready = model.launchState else { return XCTFail("store should open") }

        let podcast = try await model.subscribe(feedURL: feedURL)
        await waitForPodcastCount(model, toEqual: 1)

        // `subscribe` doesn't expose `autoAddToQueue`; flip it directly on the row, the way the
        // Library screen's podcast-settings toggle would.
        try await model.readyStore!.pool.write { db in
            try db.execute(sql: "UPDATE podcasts SET autoAddToQueue = 1 WHERE id = ?", arguments: [podcast.id.uuidString])
        }
        await waitForAutoAddToQueue(model, podcastID: podcast.id)

        LibraryStubURLProtocol.handler = { _ in .ok(Self.feedXML(episodeCount: 2)) }
        await model.refreshAll()

        await waitForQueueCount(model, toEqual: 1)
    }

    // MARK: - Fixtures

    private nonisolated static func feedXML(episodeCount: Int, titlePrefix: String = "Episode") -> Data {
        let items = (1...episodeCount).map { index in
            """
            <item>
              <title>\(titlePrefix) \(index)</title>
              <enclosure url="https://example.com/audio/\(index).mp3" length="1000" type="audio/mpeg"/>
              <pubDate>Mon, 0\(min(index, 9)) Jan 2024 00:00:00 GMT</pubDate>
            </item>
            """
        }.joined()
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
          <title>Sample Show</title>
          <description>A sample show for tests</description>
          \(items)
        </channel></rss>
        """
        return Data(xml.utf8)
    }
}

/// Minimal `URLProtocol` stub: every request is answered by the current `handler` instead of
/// reaching the network.
final class LibraryStubURLProtocol: URLProtocol {
    enum Response {
        case ok(Data)
        case httpError(statusCode: Int)
    }

    private final class HandlerBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: (@Sendable (URLRequest) -> Response)?
        func get() -> (@Sendable (URLRequest) -> Response)? { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ newValue: (@Sendable (URLRequest) -> Response)?) { lock.lock(); value = newValue; lock.unlock() }
    }

    private static let box = HandlerBox()
    static var handler: (@Sendable (URLRequest) -> Response)? {
        get { box.get() }
        set { box.set(newValue) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = Self.handler?(request) ?? .httpError(statusCode: 404)
        let url = request.url ?? URL(string: "https://example.com")!

        switch response {
        case .ok(let data):
            let httpResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .httpError(let statusCode):
            let httpResponse = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
