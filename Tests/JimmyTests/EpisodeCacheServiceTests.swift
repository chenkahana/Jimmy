#if !os(Linux)
import XCTest
@testable import Jimmy

final class EpisodeCacheServiceTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(StubURLProtocol.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(StubURLProtocol.self)
        super.tearDown()
    }

    func testUsesFreshCacheWithoutNetwork() {
        let podcast = Podcast(title: "Test", author: "A", feedURL: URL(string: "https://example.com/feed")!)
        let episodes = [Episode(id: UUID(), title: "Ep", artworkURL: nil, audioURL: URL(string: "https://a.com/1.mp3"), description: nil, played: false, podcastID: podcast.id, publishedDate: nil, localFileURL: nil, playbackPosition: 0)]
        EpisodeCacheService.shared.clearAllCache()
        EpisodeCacheService.shared.insertCache(episodes: episodes, for: podcast.id)
        StubURLProtocol.requestCount = 0
        let exp = expectation(description: "callback")
        EpisodeCacheService.shared.getEpisodes(for: podcast) { result in
            XCTAssertEqual(result.count, episodes.count)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(StubURLProtocol.requestCount, 0)
    }

    func testExpiredCacheTriggersRefresh() {
        let podcast = Podcast(title: "Test", author: "A", feedURL: URL(string: "https://example.com/feed")!)
        let episodes = [Episode(id: UUID(), title: "Ep", artworkURL: nil, audioURL: URL(string: "https://a.com/1.mp3"), description: nil, played: false, podcastID: podcast.id, publishedDate: nil, localFileURL: nil, playbackPosition: 0)]
        EpisodeCacheService.shared.clearAllCache()
        EpisodeCacheService.shared.insertCache(episodes: episodes, for: podcast.id, timestamp: Date(timeIntervalSinceNow: -3600))
        StubURLProtocol.requestCount = 0
        let exp = expectation(description: "callback")
        EpisodeCacheService.shared.getEpisodes(for: podcast) { result in
            XCTAssertEqual(result.count, episodes.count)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func testNetworkFailureUsesStaleCache() {
        let podcast = Podcast(title: "Test", author: "A", feedURL: URL(string: "https://example.com/feed")!)
        let episodes = [Episode(id: UUID(), title: "Ep", artworkURL: nil, audioURL: URL(string: "https://a.com/1.mp3"), description: nil, played: false, podcastID: podcast.id, publishedDate: nil, localFileURL: nil, playbackPosition: 0)]
        EpisodeCacheService.shared.clearAllCache()
        EpisodeCacheService.shared.insertCache(episodes: episodes, for: podcast.id, timestamp: Date(timeIntervalSinceNow: -3600))
        StubURLProtocol.requestCount = 0
        StubURLProtocol.error = NSError(domain: NSURLErrorDomain, code: -1009, userInfo: nil)
        let exp = expectation(description: "callback")
        EpisodeCacheService.shared.getEpisodes(for: podcast) { result in
            XCTAssertEqual(result.count, episodes.count)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
        StubURLProtocol.error = nil
    }
}

final class StubURLProtocol: URLProtocol {
    static var requestCount = 0
    static var stubData: Data = """
    <?xml version="1.0"?>
    <rss><channel><item><title>Ep</title><enclosure url="https://a.com/1.mp3" type="audio/mpeg"/></item></channel></rss>
    """.data(using: .utf8)!

    static var responseCode: Int = 200
    static var error: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestCount += 1
        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.responseCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.stubData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
