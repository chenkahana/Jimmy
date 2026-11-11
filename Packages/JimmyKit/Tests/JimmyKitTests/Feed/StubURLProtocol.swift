import Foundation

/// A `URLProtocol` stub for driving `FeedFetcher`/`FeedRefresher` tests without any
/// real network access. Register a handler per test via `StubURLProtocol.handler`.
final class StubURLProtocol: URLProtocol {
    /// Thread-safe box so concurrent requests (the refresher fires several at once)
    /// can all read the same handler safely.
    private final class HandlerBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: (@Sendable (URLRequest) -> StubResponse)?

        func get() -> (@Sendable (URLRequest) -> StubResponse)? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set(_ newValue: (@Sendable (URLRequest) -> StubResponse)?) {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }

    private static let box = HandlerBox()

    static var handler: (@Sendable (URLRequest) -> StubResponse)? {
        get { box.get() }
        set { box.set(newValue) }
    }

    /// Tracks the number of requests currently "in flight" (started but not yet
    /// finished), so concurrency-limit tests can assert a high-water mark.
    final class ConcurrencyTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var current = 0
        private(set) var peak = 0

        func enter() {
            lock.lock()
            current += 1
            peak = max(peak, current)
            lock.unlock()
        }

        func exit() {
            lock.lock()
            current -= 1
            lock.unlock()
        }

        func reset() {
            lock.lock()
            current = 0
            peak = 0
            lock.unlock()
        }
    }

    static let concurrencyTracker = ConcurrencyTracker()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.concurrencyTracker.enter()
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            Self.concurrencyTracker.exit()
            return
        }

        let response = handler(request)

        // Simulate a slice of real I/O latency so concurrency limits are observable.
        // This must NOT block the calling thread (`Thread.sleep`): URLSession appears to
        // serialize calls into a custom URLProtocol on a single internal queue, so a
        // protocol that blocks its own thread while "waiting" blocks the next request's
        // startLoading() too, collapsing any real concurrency down to 1. Deferring the
        // response onto a global queue lets startLoading() return immediately, so the
        // next request can start while this one is still "in flight".
        finish(after: response.delay) { [self] in
            switch response.outcome {
            case .success(let statusCode, let headers, let data):
                if let httpResponse = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: headers
                ) {
                    client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
                }
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)

            case .failure(let error):
                client?.urlProtocol(self, didFailWithError: error)
            }

            Self.concurrencyTracker.exit()
        }
    }

    private func finish(after delay: TimeInterval, _ work: @escaping () -> Void) {
        guard delay > 0 else {
            work()
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: work)
    }

    override func stopLoading() {}
}

/// A minimal lock-protected box for passing a single value out of a `StubURLProtocol`
/// handler closure (e.g. to inspect the request a test's code under test actually sent).
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}

struct StubResponse: Sendable {
    enum Outcome: Sendable {
        case success(statusCode: Int, headers: [String: String], data: Data)
        case failure(Error)
    }

    var outcome: Outcome
    var delay: TimeInterval = 0

    static func ok(data: Data, headers: [String: String] = [:], delay: TimeInterval = 0) -> StubResponse {
        StubResponse(outcome: .success(statusCode: 200, headers: headers, data: data), delay: delay)
    }

    static func notModified(delay: TimeInterval = 0) -> StubResponse {
        StubResponse(outcome: .success(statusCode: 304, headers: [:], data: Data()), delay: delay)
    }

    static func status(_ code: Int, delay: TimeInterval = 0) -> StubResponse {
        StubResponse(outcome: .success(statusCode: code, headers: [:], data: Data()), delay: delay)
    }

    static func timeout(delay: TimeInterval = 0) -> StubResponse {
        StubResponse(outcome: .failure(URLError(.timedOut)), delay: delay)
    }
}

extension URLSession {
    static func stubbed() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}
