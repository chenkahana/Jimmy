import Foundation
import Testing
@testable import JimmyKit

/// Serialized because every test in this suite (plus the `FeedRefresherTests` extension
/// in FeedRefresherTests.swift) swaps the shared `StubURLProtocol.handler` and reads its
/// `concurrencyTracker`; running them concurrently — even across the two files, since
/// Swift Testing parallelizes across suites too — would let one test's requests hit
/// another's handler, or pollute another's concurrency measurement.
@Suite(.serialized)
struct StubbedNetworkTests {
    private func makeFetcher() -> FeedFetcher {
        FeedFetcher(session: .stubbed())
    }

    @Test func successfulFetchReturnsDataAndValidators() async throws {
        let body = Data("<rss></rss>".utf8)
        StubURLProtocol.handler = { _ in
            .ok(data: body, headers: ["ETag": "\"abc123\"", "Last-Modified": "Wed, 01 Jan 2025 00:00:00 GMT"])
        }

        let result = try await makeFetcher().fetch(from: URL(string: "https://example.com/feed.xml")!, etag: nil, lastModified: nil)

        guard case let .fetched(data, etag, lastModified) = result else {
            Issue.record("expected .fetched, got \(result)")
            return
        }
        #expect(data == body)
        #expect(etag == "\"abc123\"")
        #expect(lastModified == "Wed, 01 Jan 2025 00:00:00 GMT")
    }

    @Test func notModifiedReturnsNotModifiedCase() async throws {
        StubURLProtocol.handler = { _ in .notModified() }

        let result = try await makeFetcher().fetch(
            from: URL(string: "https://example.com/feed.xml")!,
            etag: "\"abc123\"",
            lastModified: nil
        )

        #expect(result == .notModified)
    }

    @Test func conditionalHeadersAreSentWhenProvided() async throws {
        let capturedRequest = LockedBox<URLRequest?>(nil)
        StubURLProtocol.handler = { request in
            capturedRequest.set(request)
            return .ok(data: Data())
        }

        _ = try await makeFetcher().fetch(
            from: URL(string: "https://example.com/feed.xml")!,
            etag: "\"etag-value\"",
            lastModified: "Mon, 02 Jan 2025 00:00:00 GMT"
        )

        let request = capturedRequest.get()
        #expect(request?.value(forHTTPHeaderField: "If-None-Match") == "\"etag-value\"")
        #expect(request?.value(forHTTPHeaderField: "If-Modified-Since") == "Mon, 02 Jan 2025 00:00:00 GMT")
    }

    @Test func serverErrorThrowsHTTPError() async throws {
        StubURLProtocol.handler = { _ in .status(500) }

        await #expect(throws: FeedFetchError.http(statusCode: 500)) {
            _ = try await makeFetcher().fetch(from: URL(string: "https://example.com/feed.xml")!, etag: nil, lastModified: nil)
        }
    }

    @Test func timeoutThrows() async throws {
        StubURLProtocol.handler = { _ in .timeout() }

        await #expect(throws: (any Error).self) {
            _ = try await makeFetcher().fetch(from: URL(string: "https://example.com/feed.xml")!, etag: nil, lastModified: nil)
        }
    }

    @Test func defaultTimeoutIsFifteenSeconds() {
        #expect(FeedFetcher.timeout == 15)
    }
}
