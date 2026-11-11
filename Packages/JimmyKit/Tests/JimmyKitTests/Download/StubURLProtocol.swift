import Foundation

/// A stub `URLProtocol` so tests can drive `Downloads` over a plain `.ephemeral`
/// `URLSessionConfiguration` instead of a real (and un-testable) background session, while still
/// exercising the real `URLSession`/`URLSessionDownloadDelegate` machinery.
///
/// `nonisolated` to match the (synchronous, framework-called) `URLProtocol` override points;
/// its one piece of shared mutable state is a `nonisolated(unsafe)` dictionary guarded by a lock,
/// rather than `@unchecked Sendable` on the type itself.
nonisolated final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var stubs: [URL: Result<Data, Error>] = [:]

    static func stub(url: URL, data: Data) {
        lock.lock(); defer { lock.unlock() }
        stubs[url] = .success(data)
    }

    static func stub(url: URL, error: Error) {
        lock.lock(); defer { lock.unlock() }
        stubs[url] = .failure(error)
    }

    /// Removes just this URL's stub. Tests run concurrently (Swift Testing's default), so
    /// clearing the whole dictionary here would race with another test's still-in-flight stub.
    static func removeStub(url: URL) {
        lock.lock(); defer { lock.unlock() }
        stubs.removeValue(forKey: url)
    }

    private static func result(for url: URL) -> Result<Data, Error>? {
        lock.lock(); defer { lock.unlock() }
        return stubs[url]
    }

    /// Artificial delay before any response is delivered, so tests that cancel a download
    /// immediately after starting it reliably win the race against this stub resolving.
    private static let artificialDelay: TimeInterval = 0.25

    private var isCancelled = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Thread.sleep(forTimeInterval: Self.artificialDelay)
        guard !isCancelled else { return }

        guard let url = request.url, let result = Self.result(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        switch result {
        case .success(let data):
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "\(data.count)"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            // Deliver in chunks so download tasks report incremental progress.
            let chunkSize = max(1, data.count / 4)
            var offset = 0
            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                client?.urlProtocol(self, didLoad: data.subdata(in: offset..<end))
                offset = end
            }
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        isCancelled = true
    }
}
