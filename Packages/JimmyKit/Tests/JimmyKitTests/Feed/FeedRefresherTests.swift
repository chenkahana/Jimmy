import Foundation
import Testing
@testable import JimmyKit

/// See the serialization note on `StubbedNetworkTests` (FeedFetcherTests.swift) — this
/// extension's tests share that same suite and its stubbed-network state.
extension StubbedNetworkTests {
    fileprivate static let minimalFeed = Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0"><channel><title>Stub</title>
    <item><title>Ep</title><enclosure url="https://example.com/ep.mp3" type="audio/mpeg"/></item>
    </channel></rss>
    """.utf8)

    @Test func oneFailingFeedNeverFailsTheRest() async throws {
        let failingIndices: Set<Int> = [3, 9, 17]
        let requests = (0..<20).map { index in
            FeedRefreshRequest(podcastID: UUID(), feedURL: URL(string: "https://example.com/feed\(index).xml")!)
        }

        StubURLProtocol.handler = { request in
            guard let url = request.url,
                  let indexString = url.lastPathComponent
                      .replacingOccurrences(of: "feed", with: "")
                      .replacingOccurrences(of: ".xml", with: "") as String?,
                  let index = Int(indexString)
            else {
                return .status(500)
            }
            // A small delay so the 20 fetches genuinely overlap instead of completing
            // synchronously one after another.
            if failingIndices.contains(index) {
                return .status(500, delay: 0.02)
            }
            return .ok(data: Self.minimalFeed, delay: 0.02)
        }

        let outcomes = await FeedRefresher.refresh(requests, fetcher: FeedFetcher(session: .stubbed()))

        #expect(outcomes.count == 20)

        let failures = outcomes.filter {
            if case .failure = $0.result { return true }
            return false
        }
        let successes = outcomes.filter {
            if case .success = $0.result { return true }
            return false
        }

        #expect(failures.count == failingIndices.count)
        #expect(successes.count == 20 - failingIndices.count)

        // Every successful outcome actually parsed the stub feed's one episode.
        for outcome in successes {
            guard case .success(.updated(let parsed, _, _)) = outcome.result else {
                Issue.record("expected .updated for a success outcome")
                continue
            }
            #expect(parsed.episodes.count == 1)
        }
    }

    @Test func neverRunsMoreThanSixFetchesAtOnce() async throws {
        StubURLProtocol.concurrencyTracker.reset()
        let requests = (0..<20).map { index in
            FeedRefreshRequest(podcastID: UUID(), feedURL: URL(string: "https://example.com/concurrency\(index).xml")!)
        }

        StubURLProtocol.handler = { _ in .ok(data: Self.minimalFeed, delay: 0.03) }

        _ = await FeedRefresher.refresh(requests, fetcher: FeedFetcher(session: .stubbed()))

        #expect(StubURLProtocol.concurrencyTracker.peak <= FeedRefresher.maxConcurrentFetches)
        // Sanity check the test actually exercised concurrency (otherwise the <= 6
        // assertion above would pass trivially for a serial implementation too).
        #expect(StubURLProtocol.concurrencyTracker.peak > 1)
    }

    @Test func notModifiedFeedsReportNotModified() async throws {
        StubURLProtocol.handler = { _ in .notModified() }
        let requests = [FeedRefreshRequest(podcastID: UUID(), feedURL: URL(string: "https://example.com/unchanged.xml")!)]

        let outcomes = await FeedRefresher.refresh(requests, fetcher: FeedFetcher(session: .stubbed()))

        guard case .success(.notModified) = outcomes[0].result else {
            Issue.record("expected .notModified")
            return
        }
    }
}
