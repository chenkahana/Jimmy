import Foundation

/// The outcome of one conditional-GET feed fetch.
nonisolated public enum FeedFetchResult: Sendable, Equatable {
    /// Server returned 304 Not Modified — caller should keep using its cached data.
    case notModified
    /// Server returned a 2xx with a body, plus any new validators to persist.
    case fetched(data: Data, etag: String?, lastModified: String?)
}

nonisolated public enum FeedFetchError: Error, Sendable, Equatable {
    case invalidResponse
    case http(statusCode: Int)
}

/// Fetches a feed document over HTTP with conditional-GET support (`ETag` /
/// `Last-Modified`), so an unchanged feed costs a 304 instead of a full re-download.
nonisolated public struct FeedFetcher: Sendable {
    public static let timeout: TimeInterval = 15

    private let session: URLSession

    /// - Parameter session: Inject a session (e.g. one configured with a stub
    ///   `URLProtocol`) for testing. Defaults to a dedicated ephemeral session with
    ///   `timeout` applied, not `URLSession.shared`.
    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = Self.timeout
            self.session = URLSession(configuration: configuration)
        }
    }

    public func fetch(from url: URL, etag: String?, lastModified: String?) async throws -> FeedFetchResult {
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = "GET"
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedFetchError.invalidResponse
        }

        if httpResponse.statusCode == 304 {
            return .notModified
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw FeedFetchError.http(statusCode: httpResponse.statusCode)
        }

        return .fetched(
            data: data,
            etag: httpResponse.value(forHTTPHeaderField: "ETag"),
            lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified")
        )
    }
}
